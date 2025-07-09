from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from typing import Dict, List, Optional, Set

import faiss
import numpy as np
from rich import print
from rich.pretty import pprint

import fs
from pydants import write_json
from timing import Timer
import timing
from lsp.storage import FileStat, Chunk, load_chunks, chunk_id_to_faiss_id
from lsp.build import build_file_chunks, get_file_stat

#
# constants for subprocess.run for readability
IGNORE_FAILURE = False
STOP_ON_FAILURE = True

# TODO! all prints and progress must be redirected to a log once I run this INSIDE the LSP

@dataclass
class RAGDataset:
    chunks_by_file: dict[str, List[Chunk]]
    stat_by_path: dict[str, FileStat]
    index: Optional[faiss.Index] = None

@dataclass
class FilesDiff:
    # FYI type mismatch IS FINE with type hints... LEAVE IT!
    changed: Set[Path]
    deleted: Set[str]
    unchanged: Set[str]

class IncrementalRAGIndexer:

    def __init__(self, rag_dir, source_dir):
        self.rag_dir = Path(rag_dir)
        self.source_dir = Path(source_dir)

    def get_files_diff(self, language_extension: str, prior_stat_by_path: dict[str, FileStat]) -> FilesDiff:
        """Split files into: changed (added/updated), unchagned, deleted"""

        # * current files
        result = subprocess.run(
            ["fd", f".*\\.{language_extension}$", str(self.source_dir), "--absolute-path", "--type", "f"],
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
                print(f"[green]New file: {file_path}")
            else:
                current_mod_time = file_path.stat().st_mtime
                prior_mod_time = prior_stat_by_path[file_path_str].mtime
                if current_mod_time > prior_mod_time:
                    changed_paths.add(file_path)
                    print(f"[blue]Modified file: {file_path}")

        prior_path_strs: Set[str] = set(prior_stat_by_path.keys())

        # * deleted
        deleted_path_strs = prior_path_strs - current_path_strs
        for deleted_file in deleted_path_strs:
            print(f"[red]Deleted file: {deleted_file}")

        # * unchanged
        changed_path_strs = set(str(f) for f in changed_paths)
        unchanged_path_strs = prior_path_strs - changed_path_strs - deleted_path_strs

        return FilesDiff(changed_paths, deleted_path_strs, unchanged_path_strs)

    def load_prior_data(self, language_extension: str) -> RAGDataset:
        index_dir = self.rag_dir / language_extension

        vectors_index_path = index_dir / "vectors.index"
        index = None
        if vectors_index_path.exists():
            try:
                index = faiss.read_index(str(vectors_index_path))
                print(f"Loaded existing FAISS index with {index.ntotal} vectors")
            except Exception as e:
                print(f"[yellow]Warning: Could not load existing index: {e}")

        chunks_json_path = index_dir / "chunks.json"
        chunks_by_file: dict[str, List[Chunk]] = {}

        if chunks_json_path.exists():
            try:
                chunks_by_file = load_chunks(chunks_json_path)
                print(f"Loaded {len(chunks_by_file)} existing chunks")
            except Exception as e:
                print(f"[yellow]Warning: Could not load existing chunks: {e}")

        files_json_path = index_dir / "files.json"
        files_by_path = {}
        if files_json_path.exists():
            try:
                with open(files_json_path, 'r') as f:
                    files_by_path = {k: FileStat(**v) for k, v in json.load(f).items()}
                print(f"Loaded stats for {len(files_by_path)} files")
            except Exception as e:
                print(f"[yellow]Warning: Could not load file stats {e}")

        return RAGDataset(chunks_by_file, files_by_path, index)

    def update_faiss_index_incrementally(
        self,
        index: Optional[faiss.Index],
        unchanged_chunks_by_file: Dict,
        updated_chunks_by_file,
    ) -> faiss.Index:
        """Update FAISS index incrementally using IndexIDMap"""
        from lsp.model import model

        # Create base index if it doesn't exist
        if index is None:
            print("Creating new FAISS index")
            # Create a dummy vector to get dimensions
            sample_text = "passage: sample"
            sample_vec = model.encode([sample_text], normalize_embeddings=True)
            base_index = faiss.IndexFlatIP(sample_vec.shape[1])
            index = faiss.IndexIDMap(base_index)
            # FYI if someone deletes the vectors file... this won't recreate it if stat still exists...

        new_chunks = []
        new_faiss_ids = []
        for file_chunks in updated_chunks_by_file.values():
            for chunk in file_chunks:
                new_chunks.append(chunk)
                new_faiss_ids.append(chunk_id_to_faiss_id(chunk.id))

        with Timer("Remove old vectors"):
            # TODO need to pass holdovers too
            keep_ids = new_faiss_ids.copy()
            for _, file_chunks in unchanged_chunks_by_file.items():
                for chunk in file_chunks:
                    keep_ids.append(chunk_id_to_faiss_id(chunk.id))

            pretty_print("keep_ids", keep_ids)

            keep_selector = faiss.IDSelectorArray(np.array(keep_ids, dtype="int64"))
            not_keep_selector = faiss.IDSelectorNot(keep_selector)
            index.remove_ids(not_keep_selector)

        if new_chunks:
            print(f"Adding {len(new_chunks)} new vectors for changed files")

            texts = [f"passage: {chunk.text}" for chunk in new_chunks]
            print(f"{new_faiss_ids=}")

            with Timer("Encode new vectors"):
                vecs = model.encode(texts, normalize_embeddings=True, show_progress_bar=True)

            vecs_np = np.array(vecs).astype("float32")
            faiss_ids_np = np.array(new_faiss_ids, dtype="int64")

            with Timer("Add new vectors to index"):
                index.add_with_ids(vecs_np, faiss_ids_np)

        return index

    def build_index(self, language_extension: str = "lua"):
        """Build or update the RAG index incrementally"""
        print(f"[bold]Building/updating {language_extension} RAG index:")

        prior = self.load_prior_data(language_extension)

        with Timer("Find current files"):
            paths = self.get_files_diff(language_extension, prior.stat_by_path)

        # TODO add test to assert delete last file is fine and wipes the data set

        if not paths.changed and not paths.deleted:
            print("[green]No changes detected, index is up to date!")
            return

        print(f"Processing {len(paths.changed)} changed files")

        all_stat_by_path = {path_str: prior.stat_by_path[path_str] for path_str in paths.unchanged}
        unchanged_chunks_by_file = {path_str: prior.chunks_by_file[path_str] for path_str in paths.unchanged}

        updated_chunks_by_file = {}
        with Timer("Process changed files"):
            for i, file_path in enumerate(paths.changed):
                file_path_str = str(file_path)
                if i % 10 == 0 and i > 0:
                    print(f"Processed {i}/{len(paths.changed)} changed files...")

                stat = get_file_stat(file_path)
                all_stat_by_path[file_path_str] = stat

                # Create new chunks for this file
                chunks = build_file_chunks(file_path, stat.hash)
                updated_chunks_by_file[file_path_str] = chunks

        pretty_print("Deleted chunks", paths.deleted)
        pretty_print("Updated chunks", updated_chunks_by_file)
        pretty_print("Unchanged chunks", unchanged_chunks_by_file)

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
        index_dir = self.rag_dir / language_extension
        index_dir.mkdir(exist_ok=True, parents=True)

        with Timer("Save FAISS index"):
            faiss.write_index(index, str(index_dir / "vectors.index"))

        with Timer("Save chunks"):
            all_chunks_by_file = unchanged_chunks_by_file.copy()
            all_chunks_by_file.update(updated_chunks_by_file)
            pretty_print("all_chunks_by_file", all_chunks_by_file)

        with Timer("Save chunks"):
            write_json(all_chunks_by_file, index_dir / "chunks.json")

        with Timer("Save file stats"):
            write_json(all_stat_by_path, index_dir / "files.json")

        print(f"[green]Index updated successfully!")
        if paths.changed:
            print(f"[green]Processed {len(paths.changed)} changed files")
        if paths.deleted:
            print(f"[green]Removed {len(paths.deleted)} deleted files")

def trash_indexes(rag_dir, language_extension="lua"):
    """Remove index for a specific language"""
    index_path = Path(rag_dir, language_extension)
    subprocess.run(["trash", index_path], check=IGNORE_FAILURE)

def pretty_print(message, data):
    print(f"[bold]{message}:")
    pprint(data)
    print()

if __name__ == "__main__":
    verbose = "--verbose" in sys.argv
    if not verbose:
        print = lambda *_: None
        pprint = lambda *_: None
        timing.print = print

    with Timer("Total indexing time"):
        # yup, can turn this into a command that uses git repo of CWD
        root_directory = fs.get_cwd_repo_root()
        if not root_directory:
            print("[red]No Git repository found in current working directory, cannot build RAG index.")
            sys.exit(1)
        rag_dir = root_directory / ".rag"
        source_dir = "."
        print(f"[bold]RAG directory: {rag_dir}")
        indexer = IncrementalRAGIndexer(rag_dir, source_dir)
        indexer.build_index(language_extension="lua")
        indexer.build_index(language_extension="py")
        indexer.build_index(language_extension="fish")
