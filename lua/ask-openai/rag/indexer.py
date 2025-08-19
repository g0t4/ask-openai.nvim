from dataclasses import dataclass
import logging
from pathlib import Path
import subprocess
import sys
from typing import Dict, Optional, Set

# * TORCH BEFORE FAISS (even if don't need torch here/yet)
import torch  # MUST be imported BEFORE FAISS else Qwen3 will explode on model import
import faiss
import numpy as np

import fs
from pydants import write_json
from lsp.storage import Chunk, FileStat, load_prior_data
from lsp.chunker import build_chunks_from_file, build_ts_chunks, get_file_stat

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
    not_changed: Set[str]

class IncrementalRAGIndexer:

    def __init__(self, dot_rag_dir, source_code_dir, model_wrapper, enable_ts_chunks):
        self.enable_ts_chunks = enable_ts_chunks
        self.dot_rag_dir = Path(dot_rag_dir)
        self.source_code_dir = Path(source_code_dir)
        self.model_wrapper = model_wrapper

    def main(self):
        exts = self.get_included_extensions()
        for ext in exts:
            self.build_index(ext)
        self.warn_about_other_extensions(exts)

    def get_included_extensions(self):
        rag_yaml = self.source_code_dir / ".rag.yaml"
        if not rag_yaml.exists():
            logger.debug(f"no rag config found {rag_yaml}, using default config")
            return ["lua", "py", "fish"]
        import yaml
        with open(rag_yaml, "r") as f:
            config = yaml.safe_load(f)
            logger.pp_debug(f"found rag config: {rag_yaml}", config)
            return config["include"]

    def warn_about_other_extensions(self, index_languages: list[str]):

        result = subprocess.run(
            ["fish", "-c", f"fd {self.source_code_dir} --exclude='\\.ctags\\.d' --exclude='\\.rag' --exec basename"],
            stdout=subprocess.PIPE,
            text=True,
            check=STOP_ON_FAILURE,
        )
        basenames = result.stdout.strip().splitlines()

        ignore_files = ["ctags", "ctags.d"]

        extensions = [basename.split(".")[-1] \
            for basename in basenames \
            if basename and "." in basename \
            and basename not in ignore_files
        ]

        import itertools
        unindexed_extensions = [(ext, len(list(group))) \
            for ext, group in itertools.groupby(sorted(extensions)) \
            if ext not in index_languages
        ]

        # TODO pair with an ignore style file for what not to index in a given repo

        # require at least 2 of a file before warning
        #   within one file you don't need RAG for context :)
        noteworthy_extensions = [ \
            f"{ext}={count}" \
            for ext, count in unindexed_extensions \
            if count > 1
        ]

        if noteworthy_extensions:
            logger.debug(f"Found unindexed extensions: {' '.join(noteworthy_extensions)}")

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
                logger.debug(f"[green]New file: {file_path}")
            else:
                current_mod_time = file_path.stat().st_mtime
                prior_mod_time = prior_stat_by_path[file_path_str].mtime
                if current_mod_time > prior_mod_time:
                    changed_paths.add(file_path)
                    logger.debug(f"[blue]Modified file: {file_path}")

        prior_path_strs: Set[str] = set(prior_stat_by_path.keys())

        # * deleted
        deleted_path_strs = prior_path_strs - current_path_strs
        for deleted_file in deleted_path_strs:
            logger.debug(f"[red]Deleted file: {deleted_file}")

        # * not changed
        changed_path_strs = set(str(f) for f in changed_paths)
        not_changed_path_strs = prior_path_strs - changed_path_strs - deleted_path_strs

        return FilesDiff(changed_paths, deleted_path_strs, not_changed_path_strs)

    def update_faiss_index_incrementally(
        self,
        index: Optional[faiss.Index],
        not_changed_chunks_by_file: dict[str, list[Chunk]],
        updated_chunks_by_file: dict[str, list[Chunk]],
    ) -> faiss.Index:
        """Update FAISS index incrementally using IndexIDMap"""

        # Create base index if it doesn't exist
        if index is None:
            shape = self.model_wrapper.get_shape()
            # 768 for "intfloat/e5-base-v2"
            # 1024 for Qwen3
            base_index = faiss.IndexFlatIP(shape)
            index = faiss.IndexIDMap(base_index)
            # FYI if someone deletes the vectors file... this won't recreate it if stat still exists...

        new_chunks: list[Chunk] = []
        new_faiss_ids: list[int] = []
        for file_chunks in updated_chunks_by_file.values():
            for chunk in file_chunks:
                new_chunks.append(chunk)
                new_faiss_ids.append(chunk.faiss_id)

        # FYI FIX THE updated check logic... don't try to work around it here
        #  fix it so a chunk that is VERBATIM same content is NOT marked updated just b/c another part of the file is... OR just b/c timestamp on file changes!
        keep_ids = []  # why was I keeping things that are marked updated?!
        logger.pp_debug("keep_ids - before", keep_ids)
        for _, file_chunks in not_changed_chunks_by_file.items():
            for chunk in file_chunks:
                keep_ids.append(chunk.faiss_id)
        logger.pp_debug("keep_ids - after", keep_ids)

        # BUG: currently updated files, the chunks that don't change (or entire thing if just msec updated)...
        #   these chunks IDs are put into keep_ids AND chunks go into new_chunks
        #   and so we insert them again (double them up)
        keep_selector = faiss.IDSelectorArray(np.array(keep_ids, dtype="int64"))
        not_keep_selector = faiss.IDSelectorNot(keep_selector)
        index.remove_ids(not_keep_selector)

        if new_chunks:
            logger.pp_debug("new_faiss_ids", new_faiss_ids)

            with logger.timer("Encode new vectors"):
                passages = [chunk.text for chunk in new_chunks]
                vecs_np = self.model_wrapper.encode_passages(passages)

            faiss_ids_np = np.array(new_faiss_ids, dtype="int64")

            index.add_with_ids(vecs_np, faiss_ids_np)

        return index

    def build_index(self, language_extension: str = "lua"):
        """Build or update the RAG index incrementally"""

        prior = load_prior_data(self.dot_rag_dir, language_extension)

        paths = self.get_files_diff(language_extension, prior.stat_by_path)

        # TODO add test to assert delete last file is fine and wipes the data set

        logger.pp_debug("paths", paths)

        if not paths.changed and not paths.deleted:
            logger.debug("[green]No changes detected, index is up to date!")
            return

        all_stat_by_path = {path_str: prior.stat_by_path[path_str] for path_str in paths.not_changed}
        not_changed_chunks_by_file = {path_str: prior.chunks_by_file[path_str] for path_str in paths.not_changed}
        logger.info(f'{len(paths.changed)} changed, {len(paths.deleted)} deleted')

        updated_chunks_by_file: dict[str, list[Chunk]] = {}
        for file_path in paths.changed:
            file_path_str = str(file_path)

            stat = get_file_stat(file_path)
            all_stat_by_path[file_path_str] = stat

            # Create new chunks for this file
            chunks = build_chunks_from_file(file_path, stat.hash)
            if self.enable_ts_chunks:
                ts_chunks = build_ts_chunks(file_path, stat.hash)
                chunks.extend(ts_chunks)
            updated_chunks_by_file[file_path_str] = chunks

        logger.pp_debug("Deleted chunks", paths.deleted)
        logger.pp_debug("Updated chunks", updated_chunks_by_file)
        logger.pp_debug("NOT changed chunks", not_changed_chunks_by_file)

        # * Incrementally update the FAISS index
        if paths.changed or paths.deleted:
            index = self.update_faiss_index_incrementally(
                prior.index,
                not_changed_chunks_by_file,
                updated_chunks_by_file,
            )
        else:
            index = prior.index

        if index is None:
            return

        # Save everything
        index_dir = self.dot_rag_dir / language_extension
        index_dir.mkdir(exist_ok=True, parents=True)

        faiss.write_index(index, str(index_dir / "vectors.index"))

        logger.pp_debug("ids: ", prior.index_view.ids)

        with logger.timer("Save chunks"):
            all_chunks_by_file = not_changed_chunks_by_file.copy()
            all_chunks_by_file.update(updated_chunks_by_file)
            logger.pp_debug("all_chunks_by_file", all_chunks_by_file)
            logger.pp_debug("all_stat_by_path", all_stat_by_path)

        with logger.timer("Save chunks"):
            write_json(all_chunks_by_file, index_dir / "chunks.json")

        with logger.timer("Save file stats"):
            write_json(all_stat_by_path, index_dir / "files.json")

        logger.debug(f"[green]Index updated successfully!")
        if paths.changed:
            logger.debug(f"[green]Processed {len(paths.changed)} changed files")
        if paths.deleted:
            logger.debug(f"[green]Removed {len(paths.deleted)} deleted files")

def trash_dot_rag(dot_rag_dir):
    dot_rag_dir = Path(dot_rag_dir)
    if not dot_rag_dir.exists():
        return
    subprocess.run(["trash", dot_rag_dir], check=IGNORE_FAILURE)

def main():
    from lsp.logs import logging_fwk_to_console
    from lsp import model_qwen3_remote as model_wrapper

    # * command line args
    verbose = "--verbose" in sys.argv or "--debug" in sys.argv
    info = "--info" in sys.argv
    level = logging.DEBUG if verbose else (logging.INFO if info else logging.WARNING)
    rebuild = "--rebuild" in sys.argv
    in_githook = "--githook" in sys.argv
    if in_githook:
        # for now bump level to INFO until I get the hooks stabilized (i.e. not running indexer twice)
        level = logging.INFO

    logging_fwk_to_console(level)

    with logger.timer("Total indexing time"):
        # yup, can turn this into a command that uses git repo of CWD
        root_directory = fs.get_cwd_repo_root()
        if not root_directory:
            logger.error("[red]No Git repository found in current working directory, cannot build RAG index.")
            sys.exit(1)
        dot_rag_dir = root_directory / ".rag"
        source_code_dir = "."  # TODO make this root_directory always? has been nice to test a subset of files by cd to nested dir
        logger.debug(f"[bold]RAG directory: {dot_rag_dir}")
        if rebuild:
            trash_dot_rag(dot_rag_dir)
        indexer = IncrementalRAGIndexer(dot_rag_dir, source_code_dir, model_wrapper, enable_ts_chunks=True)
        indexer.main()

if __name__ == "__main__":
    main()
