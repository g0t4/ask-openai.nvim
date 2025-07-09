from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from typing import Dict, List, Optional, TypeAlias, Set

import faiss
import numpy as np
from pydantic import BaseModel
from rich import print
from rich.pretty import pprint

from pydants import write_json
import fs
from lsp.ids import chunk_id_to_faiss_id
from timing import Timer
import timing
#
# constants for subprocess.run for readability
IGNORE_FAILURE = False
STOP_ON_FAILURE = True

# TODO! all prints and progress must be redirected to a log once I run this INSIDE the LSP

class FileMeta(BaseModel):
    mtime: float
    size: int
    hash: str
    path: str

class Chunk(BaseModel):
    id: str
    id_int: str
    text: str
    file: str
    start_line: int
    end_line: int
    type: str
    file_hash: str

# FYI using str for key (file path) currently, don't need to change it to Path, it's fine as is
ChunksByFile: TypeAlias = dict[str, List[Chunk]]
FileMetadataByPath: TypeAlias = dict[str, FileMeta]

@dataclass
class RAGDataset:
    chunks_by_file: ChunksByFile
    files_by_path: FileMetadataByPath
    index: Optional[faiss.Index] = None

@dataclass
class FilesDiff:
    # FYI type mismatch IS FINE with type hints... LEAVE IT!
    changed: Set[Path]
    deleted: Set[str]

class IncrementalRAGIndexer:

    def __init__(self, rag_dir, source_dir):
        self.rag_dir = Path(rag_dir)
        self.source_dir = Path(source_dir)

    def get_file_hash(self, file_path: Path) -> str:
        hasher = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hasher.update(chunk)
        return hasher.hexdigest()

    def get_file_metadata(self, file_path: Path) -> FileMeta:
        stat = file_path.stat()
        return FileMeta(
            mtime=stat.st_mtime,
            size=stat.st_size,
            hash=self.get_file_hash(file_path),
            path=str(file_path)  # for serializing and reading by LSP
        )

    def generate_chunk_id(self, file_path: Path, chunk_type: str, start_line: int, end_line: int, file_hash: str) -> str:
        """Generate unique chunk ID based on file path, chunk index, and file hash"""
        chunk_str = f"{file_path}:{chunk_type}:{start_line}-{end_line}:{file_hash}"
        return hashlib.sha256(chunk_str.encode()).hexdigest()[:16]

    def build_file_chunks(self, path: Path, file_hash: str, lines_per_chunk: int = 20, overlap: int = 5) -> List[Dict]:
        """Chunk a file with unique chunk IDs"""
        chunks = []
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        def iter_chunks(lines, lines_per_chunk=20, overlap=4, min_chunk_size=10):
            n_lines = len(lines)
            step = lines_per_chunk - overlap
            for idx, i in enumerate(range(0, n_lines, step)):
                start = i
                end_line = min(i + lines_per_chunk, n_lines)
                if (end_line - start) < min_chunk_size and idx > 0:
                    break

                chunk_type = "lines"
                start_line = start + 1
                chunk_id = self.generate_chunk_id(path, chunk_type, start_line, end_line, file_hash)
                yield Chunk(
                    id=chunk_id,
                    id_int=str(chunk_id_to_faiss_id(chunk_id)),
                    text="".join(lines[start:end_line]).strip(),
                    file=str(path),
                    start_line=start_line,
                    end_line=end_line,
                    type=chunk_type,
                    file_hash=file_hash,
                )

        for _, chunk in enumerate(iter_chunks(lines, lines_per_chunk, overlap)):
            chunks.append(chunk)
        return chunks

    def get_files_for(self, language_extension: str) -> List[Path]:
        """Find files using fd command"""
        result = subprocess.run(
            ["fd", f".*\\.{language_extension}$", str(self.source_dir), "--absolute-path", "--type", "f"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        return [Path(line) for line in result.stdout.strip().splitlines()]

    def load_prior_index(self, language_extension: str) -> RAGDataset:
        """Load existing (aka prior) index, chunks, and file metadata"""
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
        chunks_by_file: ChunksByFile = {}

        if chunks_json_path.exists():
            try:
                with open(chunks_json_path, 'r') as f:
                    chunks_by_file = {k: [Chunk(**v) for v in v] for k, v in json.load(f).items()}
                print(f"Loaded {len(chunks_by_file)} existing chunks")
            except Exception as e:
                print(f"[yellow]Warning: Could not load existing chunks: {e}")

        files_json_path = index_dir / "files.json"
        files_by_path = {}
        if files_json_path.exists():
            try:
                with open(files_json_path, 'r') as f:
                    files_by_path = {k: FileMeta(**v) for k, v in json.load(f).items()}
                print(f"Loaded metadata for {len(files_by_path)} files")
            except Exception as e:
                print(f"[yellow]Warning: Could not load file metadata: {e}")

        return RAGDataset(chunks_by_file, files_by_path, index)

    def get_file_changes(self, current_files: List[Path], prior_metadata_by_path: FileMetadataByPath) -> FilesDiff:
        """Find files that have changed or are new, and files that were deleted"""
        changed_file_paths: Set[Path] = set()
        current_file_paths: Set[str] = {str(f) for f in current_files}
        prior_file_paths: Set[str] = set(prior_metadata_by_path.keys())

        for file_path in current_files:
            file_path_str = str(file_path)
            is_new_file = file_path_str not in prior_metadata_by_path
            if is_new_file:
                changed_file_paths.add(file_path)
                print(f"[green]New file: {file_path}")
            else:
                current_mod_time = file_path.stat().st_mtime
                prior_mod_time = prior_metadata_by_path[file_path_str].mtime
                if current_mod_time > prior_mod_time:
                    changed_file_paths.add(file_path)
                    print(f"[blue]Modified file: {file_path}")

        # Find deleted files
        deleted_file_paths = prior_file_paths - current_file_paths
        for deleted_file in deleted_file_paths:
            print(f"[red]Deleted file: {deleted_file}")

        return FilesDiff(changed_file_paths, deleted_file_paths)

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
            # FYI if someone deletes the vectors file... this won't recreate it if metadata still exists...

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

            print("[bold]keep_ids:")
            pprint(keep_ids)
            print()

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

        prior = self.load_prior_index(language_extension)

        with Timer("Find current files"):
            current_file_paths = self.get_files_for(language_extension)
            print(f"Found {len(current_file_paths)} {language_extension} files")

        # FYI allow NO files to CLEAR everything! and add some tests that use this!

        files_diff = self.get_file_changes(current_file_paths, prior.files_by_path)

        if not files_diff.changed and not files_diff.deleted:
            print("[green]No changes detected, index is up to date!")
            return

        print(f"Processing {len(files_diff.changed)} changed files")

        # * Process changed files
        new_file_metadata = prior.files_by_path.copy()
        unchanged_chunks_by_file = prior.chunks_by_file.copy()

        # Remove metadata and chunks for deleted files, since we started with prior lists
        deleted_chunks_by_file = {}
        for path_str in files_diff.deleted:
            if path_str in new_file_metadata:
                # make sure file metadata doesn't get copied into new file list
                del new_file_metadata[path_str]
            if path_str in unchanged_chunks_by_file:
                deleted_chunks_by_file[path_str] = unchanged_chunks_by_file[path_str]
                del unchanged_chunks_by_file[path_str]

        updated_chunks_by_file = {}
        with Timer("Process changed files"):
            for i, file_path in enumerate(files_diff.changed):
                file_path_str = str(file_path)
                if i % 10 == 0 and i > 0:
                    print(f"Processed {i}/{len(files_diff.changed)} changed files...")

                metadata = self.get_file_metadata(file_path)
                new_file_metadata[file_path_str] = metadata

                # Create new chunks for this file
                chunks = self.build_file_chunks(file_path, metadata.hash)
                updated_chunks_by_file[file_path_str] = chunks

                if file_path_str in unchanged_chunks_by_file:
                    # remove from original list as this is changed...
                    del unchanged_chunks_by_file[file_path_str]

        print("[bold]Deleted chunks:")
        pprint(deleted_chunks_by_file)
        print()
        print("[bold]Updated chunks:")
        pprint(updated_chunks_by_file)
        print()
        print(f"[bold]Unchanged chunks:")
        pprint(unchanged_chunks_by_file)
        print()

        # * Incrementally update the FAISS index
        if files_diff.changed or files_diff.deleted:
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
            print()
            print(f"[bold]all_chunks_by_file:")
            pprint(all_chunks_by_file)
            print()

        with Timer("Save chunks"):
            write_json(all_chunks_by_file, index_dir / "chunks.json")

        with Timer("Save file metadata"):
            write_json(new_file_metadata, index_dir / "files.json")

        print(f"[green]Index updated successfully!")
        if files_diff.changed:
            print(f"[green]Processed {len(files_diff.changed)} changed files")
        if files_diff.deleted:
            print(f"[green]Removed {len(files_diff.deleted)} deleted files")

def trash_indexes(rag_dir, language_extension="lua"):
    """Remove index for a specific language"""
    index_path = Path(rag_dir, language_extension)
    subprocess.run(["trash", index_path], check=IGNORE_FAILURE)

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
