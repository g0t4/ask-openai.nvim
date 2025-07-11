from dataclasses import dataclass
import logging
from pathlib import Path
import subprocess
import sys
from typing import Dict, Optional, Set

import faiss
import numpy as np

import fs
from pydants import write_json
from lsp.storage import Chunk, FileStat, load_prior_data
from lsp.build import build_file_chunks, get_file_stat
from lsp.model import model_wrapper

from lsp.logs import get_logger

logger = get_logger(__name__)

#
# constants for subprocess.run for readability
IGNORE_FAILURE = False
STOP_ON_FAILURE = True

@dataclass
class FilesDiff:
    # FYI type mismatch IS FINE with type hints... LEAVE IT!
    changed: Set[Path]
    deleted: Set[str]
    unchanged: Set[str]

class IncrementalRAGIndexer:

    def __init__(self, dot_rag_dir, source_code_dir):
        self.dot_rag_dir = Path(dot_rag_dir)
        self.source_code_dir = Path(source_code_dir)

    def get_files_diff(self, language_extension: str, prior_stat_by_path: dict[str, FileStat]) -> FilesDiff:
        """Split files into: changed (added/updated), unchagned, deleted"""

        # PRN add in gitignore detection, right now I am using fd so I s/b mostly fine, still might want explicit checks here too
        #   use whatever I come up with from LS's text document events to filter... i.e. files in a .venv that I open (F12)
        #    though that again isn't an issue for this part of indexing
        # PRN add .ask.config or similar w/ ignore section to block things like manual_prompting folder! in ask-openai repo!

        # * current files
        result = subprocess.run(
            ["fd", f".*\\.{language_extension}$", str(self.source_code_dir), "--absolute-path", "--type", "f"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        current_path_strs = set(result.stdout.strip().splitlines())

        # * added, modified (aka changed)
        changed_paths: Set[Path] = set()
        for file_path_str in current_path_strs:
            file_path = Path(file_path_str)
            is_new_file = file_path_str not in prior_stat_by_path
            if is_new_file:
                changed_paths.add(file_path)
                logger.info(f"[green]New file: {file_path}")
            else:
                current_mod_time = file_path.stat().st_mtime
                prior_mod_time = prior_stat_by_path[file_path_str].mtime
                if current_mod_time > prior_mod_time:
                    changed_paths.add(file_path)
                    logger.info(f"[blue]Modified file: {file_path}")

        prior_path_strs: Set[str] = set(prior_stat_by_path.keys())

        # * deleted
        deleted_path_strs = prior_path_strs - current_path_strs
        for deleted_file in deleted_path_strs:
            logger.info(f"[red]Deleted file: {deleted_file}")

        # * unchanged
        changed_path_strs = set(str(f) for f in changed_paths)
        unchanged_path_strs = prior_path_strs - changed_path_strs - deleted_path_strs

        return FilesDiff(changed_paths, deleted_path_strs, unchanged_path_strs)

    def update_faiss_index_incrementally(
        self,
        index: Optional[faiss.Index],
        unchanged_chunks_by_file: dict[str, list[Chunk]],
        updated_chunks_by_file: dict[str, list[Chunk]],
    ) -> faiss.Index:
        """Update FAISS index incrementally using IndexIDMap"""

        # Create base index if it doesn't exist
        if index is None:
            logger.info("Creating new FAISS index")
            shape = model_wrapper.get_shape()
            logger.info(f"{shape=}")  # 768 for current model
            base_index = faiss.IndexFlatIP(shape)
            index = faiss.IndexIDMap(base_index)
            # FYI if someone deletes the vectors file... this won't recreate it if stat still exists...

        new_chunks: list[Chunk] = []
        new_faiss_ids: list[int] = []
        for file_chunks in updated_chunks_by_file.values():
            for chunk in file_chunks:
                new_chunks.append(chunk)
                new_faiss_ids.append(chunk.faiss_id)

        with logger.timer("Remove old vectors"):
            # TODO need to pass holdovers too
            keep_ids = new_faiss_ids.copy()
            for _, file_chunks in unchanged_chunks_by_file.items():
                for chunk in file_chunks:
                    keep_ids.append(chunk.faiss_id)

            logger.pp_info("keep_ids", keep_ids)

            keep_selector = faiss.IDSelectorArray(np.array(keep_ids, dtype="int64"))
            not_keep_selector = faiss.IDSelectorNot(keep_selector)
            index.remove_ids(not_keep_selector)

        if new_chunks:
            logger.info(f"Adding {len(new_chunks)} new vectors for changed files")

            logger.info(f"{new_faiss_ids=}")

            with logger.timer("Encode new vectors"):
                passages = [chunk.text for chunk in new_chunks]
                vecs = model_wrapper.encode_passages(passages, show_progress_bar=True)

            # PRN move these np.array transforms into encode* funcs?
            #  TODO IIRC  model.encode has a numpy param for this purpose!
            vecs_np = np.array(vecs).astype("float32")
            faiss_ids_np = np.array(new_faiss_ids, dtype="int64")

            with logger.timer("Add new vectors to index"):
                index.add_with_ids(vecs_np, faiss_ids_np)

        return index

    def build_index(self, language_extension: str = "lua"):
        """Build or update the RAG index incrementally"""
        logger.info(f"[bold]Building/updating {language_extension} RAG index:")

        prior = load_prior_data(language_extension, self.dot_rag_dir)

        with logger.timer("Find current files"):
            paths = self.get_files_diff(language_extension, prior.stat_by_path)

        # TODO add test to assert delete last file is fine and wipes the data set

        if not paths.changed and not paths.deleted:
            logger.info("[green]No changes detected, index is up to date!")
            return

        logger.info(f"Processing {len(paths.changed)} changed files")

        all_stat_by_path = {path_str: prior.stat_by_path[path_str] for path_str in paths.unchanged}
        unchanged_chunks_by_file = {path_str: prior.chunks_by_file[path_str] for path_str in paths.unchanged}

        updated_chunks_by_file: dict[str, list[Chunk]] = {}
        with logger.timer("Process changed files"):
            for i, file_path in enumerate(paths.changed):
                file_path_str = str(file_path)
                if i % 10 == 0 and i > 0:
                    logger.info(f"Processed {i}/{len(paths.changed)} changed files...")

                stat = get_file_stat(file_path)
                all_stat_by_path[file_path_str] = stat

                # Create new chunks for this file
                chunks = build_file_chunks(file_path, stat.hash)
                updated_chunks_by_file[file_path_str] = chunks

        logger.pp_info("Deleted chunks", paths.deleted)
        logger.pp_info("Updated chunks", updated_chunks_by_file)
        logger.pp_info("Unchanged chunks", unchanged_chunks_by_file)

        # * Incrementally update the FAISS index
        if paths.changed or paths.deleted:
            index = self.update_faiss_index_incrementally(
                prior.index,
                unchanged_chunks_by_file,
                updated_chunks_by_file,
            )
        else:
            index = prior.index

        if index is None:
            return

        # Save everything
        index_dir = self.dot_rag_dir / language_extension
        index_dir.mkdir(exist_ok=True, parents=True)

        with logger.timer("Save FAISS index"):
            faiss.write_index(index, str(index_dir / "vectors.index"))

        with logger.timer("Save chunks"):
            all_chunks_by_file = unchanged_chunks_by_file.copy()
            all_chunks_by_file.update(updated_chunks_by_file)
            logger.pp_info("all_chunks_by_file", all_chunks_by_file)

        with logger.timer("Save chunks"):
            write_json(all_chunks_by_file, index_dir / "chunks.json")

        with logger.timer("Save file stats"):
            write_json(all_stat_by_path, index_dir / "files.json")

        logger.info(f"[green]Index updated successfully!")
        if paths.changed:
            logger.info(f"[green]Processed {len(paths.changed)} changed files")
        if paths.deleted:
            logger.info(f"[green]Removed {len(paths.deleted)} deleted files")

def trash_indexes(dot_rag_dir, language_extension="lua"):
    """Remove index for a specific language"""
    index_path = Path(dot_rag_dir, language_extension)
    subprocess.run(["trash", index_path], check=IGNORE_FAILURE)

if __name__ == "__main__":
    from lsp.logs import use_console

    verbose = "--verbose" in sys.argv
    level = logging.DEBUG if verbose else logging.WARN
    use_console(level)
    # FYI won't log w/o this call, not from logging fwk

    with logger.timer("Total indexing time"):
        # yup, can turn this into a command that uses git repo of CWD
        root_directory = fs.get_cwd_repo_root()
        if not root_directory:
            logger.info("[red]No Git repository found in current working directory, cannot build RAG index.")
            sys.exit(1)
        dot_rag_dir = root_directory / ".rag"
        source_code_dir = "."
        logger.info(f"[bold]RAG directory: {dot_rag_dir}")
        indexer = IncrementalRAGIndexer(dot_rag_dir, source_code_dir)
        indexer.build_index(language_extension="lua")
        indexer.build_index(language_extension="py")
        indexer.build_index(language_extension="fish")
