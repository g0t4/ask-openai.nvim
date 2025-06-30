import hashlib
import json
from pathlib import Path
import subprocess
import sys
from typing import Dict, List, Optional, Set, Tuple

import faiss
import numpy as np
from rich import print

import fs
from lsp.ids import chunk_id_to_faiss_id
from timing import Timer
# constants for subprocess.run for readability
IGNORE_FAILURE = False
STOP_ON_FAILURE = True

#! FYI! this works with a rebuild (nuk the dir tmp/rag_index)
#! TODO! all prints and progress must be redirected to a log once I run this INSIDE the LSP
# !!! DO NOT USE INCREMENTAL REBUILD UNTIL FIX ORDERING ISSUE WITH DELETES
#! TODO! fix the cluster F of deleting chunks and then requerying them... in build_index... chicken egg and Claude Foo'd it up bad

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

    def get_file_metadata(self, file_path: Path) -> Dict:
        stat = file_path.stat()
        return {
            'path': str(file_path),
            'hash': self.get_file_hash(file_path),
            'mtime': stat.st_mtime,
            'size': stat.st_size,
        }

    def generate_chunk_id(self, file_path: Path, chunk_type: str, start_line: int, end_line: int, file_hash: str) -> str:
        """Generate unique chunk ID based on file path, chunk index, and file hash"""
        chunk_str = f"{file_path}:{chunk_type}:{start_line}-{end_line}:{file_hash}"
        return hashlib.sha256(chunk_str.encode()).hexdigest()[:16]

    def get_file_chunks(self, path: Path, file_hash: str, lines_per_chunk: int = 20, overlap: int = 5) -> List[Dict]:
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
                yield {
                    "id": chunk_id,
                    "id_int": str(chunk_id_to_faiss_id(chunk_id)),
                    "text": "".join(lines[start:end_line]).strip(),
                    "file": str(path),
                    "start_line": start_line,
                    "end_line": end_line,
                    "type": chunk_type,
                    "file_hash": file_hash,
                }

        for _, chunk in enumerate(iter_chunks(lines, lines_per_chunk, overlap)):
            chunks.append(chunk)
        return chunks

    def find_files_with_fd(self, language_extension: str) -> List[Path]:
        """Find files using fd command"""
        result = subprocess.run(
            ["fd", f".*\\.{language_extension}$", str(self.source_dir), "--absolute-path", "--type", "f"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        return [Path(line) for line in result.stdout.strip().splitlines()]

    def load_existing_index(self, language_extension: str) -> Tuple[Optional[faiss.Index], Dict, Dict]:
        """Load existing index, chunks, and file metadata"""
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
        chunks_by_id = {}
        if chunks_json_path.exists():
            try:
                with open(chunks_json_path, 'r') as f:
                    chunks_list = json.load(f)
                    chunks_by_id = {chunk['id']: chunk for chunk in chunks_list}
                print(f"Loaded {len(chunks_by_id)} existing chunks")
            except Exception as e:
                print(f"[yellow]Warning: Could not load existing chunks: {e}")

        files_json_path = index_dir / "files.json"
        files = {}
        if files_json_path.exists():
            try:
                with open(files_json_path, 'r') as f:
                    files = json.load(f)
                print(f"Loaded metadata for {len(files)} files")
            except Exception as e:
                print(f"[yellow]Warning: Could not load file metadata: {e}")

        return index, chunks_by_id, files

    def find_changed_files(self, current_files: List[Path], existing_metadata: Dict) -> Tuple[Set[Path], Set[str]]:
        """Find files that have changed or are new, and files that were deleted"""
        changed_files = set()
        current_file_paths = {str(f) for f in current_files}
        existing_file_paths = set(existing_metadata.keys())

        # Check for new and modified files
        for file_path in current_files:
            file_str = str(file_path)
            if file_str not in existing_metadata:
                # New file
                changed_files.add(file_path)
                print(f"[green]New file: {file_path}")
            else:
                # Check if file has changed
                current_mtime = file_path.stat().st_mtime
                existing_mtime = existing_metadata[file_str]['mtime']
                if current_mtime > existing_mtime:
                    changed_files.add(file_path)
                    print(f"[blue]Modified file: {file_path}")

        # Find deleted files
        deleted_files = existing_file_paths - current_file_paths
        for deleted_file in deleted_files:
            print(f"[red]Deleted file: {deleted_file}")

        return changed_files, deleted_files

    def remove_chunks_for_deleted_files(self, chunks: Dict, deleted_files: Set[str]) -> Dict:
        """Remove chunks for deleted files"""
        chunks_to_remove = []
        for chunk_id, chunk in chunks.items():
            if chunk['file'] in deleted_files:
                chunks_to_remove.append(chunk_id)

        for chunk_id in chunks_to_remove:
            del chunks[chunk_id]

        if chunks_to_remove:
            print(f"Removed {len(chunks_to_remove)} chunks for deleted files")

        return chunks

    def get_chunks_for_files(self, chunks: Dict, file_paths: Set[str]) -> Set[str]:
        """Get all chunk IDs for the given file paths"""
        chunk_ids = set()
        for chunk_id, chunk in chunks.items():
            if chunk['file'] in file_paths:
                chunk_ids.add(chunk_id)
        return chunk_ids

    def update_faiss_index_incrementally(self, index: Optional[faiss.Index], chunks: Dict, changed_files: Set[Path], deleted_files: Set[str]) -> faiss.Index:
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

        # Remove vectors for changed and deleted files
        files_to_remove = set(str(f) for f in changed_files) | deleted_files
        if files_to_remove:
            chunk_ids_to_remove = self.get_chunks_for_files(chunks, files_to_remove)
            if chunk_ids_to_remove:
                faiss_ids_to_remove = [chunk_id_to_faiss_id(cid) for cid in chunk_ids_to_remove]
                print(f"Removing {len(faiss_ids_to_remove)} vectors for changed/deleted files")

                with Timer("Remove old vectors"):
                    selector = faiss.IDSelectorArray(np.array(faiss_ids_to_remove, dtype="int64"))
                    index.remove_ids(selector)

        # Add vectors for changed files only
        if changed_files:
            new_chunks = []
            new_chunk_ids = []

            for file_path in changed_files:
                for chunk_id, chunk in chunks.items():
                    if chunk['file'] == str(file_path):
                        new_chunks.append(chunk)
                        new_chunk_ids.append(chunk_id)

            if new_chunks:
                print(f"Adding {len(new_chunks)} new vectors for changed files")

                texts = [f"passage: {chunk['text']}" for chunk in new_chunks]
                faiss_ids = [chunk_id_to_faiss_id(cid) for cid in new_chunk_ids]
                print(f"{faiss_ids=}")

                with Timer("Encode new vectors"):
                    vecs = model.encode(texts, normalize_embeddings=True, show_progress_bar=True)

                vecs_np = np.array(vecs).astype("float32")
                faiss_ids_np = np.array(faiss_ids, dtype="int64")

                with Timer("Add new vectors to index"):
                    index.add_with_ids(vecs_np, faiss_ids_np)

        return index

    def build_index(self, language_extension: str = "lua"):
        """Build or update the RAG index incrementally"""
        print(f"[bold]Building/updating {language_extension} RAG index:")

        existing_index, existing_chunks_by_id, existing_file_metadata = self.load_existing_index(language_extension)

        with Timer("Find current files"):
            current_files = self.find_files_with_fd(language_extension)
            print(f"Found {len(current_files)} {language_extension} files")

        if not current_files:
            print("[red]No files found, no index to build")
            return

        changed_files, deleted_files = self.find_changed_files(current_files, existing_file_metadata)

        if not changed_files and not deleted_files:
            print("[green]No changes detected, index is up to date!")
            return

        print(f"Processing {len(changed_files)} changed files")

        # TODO this shouldn't be deleting the chunks that are then tried to be usedlater...
        # TODO at least capture the ids of what were remoged into one collection
        # TODO just OMG I hate this whole pilee of crap
        # TODO later wes
        chunks = self.remove_chunks_for_deleted_files(existing_chunks_by_id, deleted_files)

        # * Process changed files
        new_file_metadata = existing_file_metadata.copy()

        # Remove metadata and chunks for deleted files
        for deleted_file in deleted_files:
            if deleted_file in new_file_metadata:
                del new_file_metadata[deleted_file]

        with Timer("Process changed files"):
            for i, file_path in enumerate(changed_files):
                if i % 10 == 0 and i > 0:
                    print(f"Processed {i}/{len(changed_files)} changed files...")

                # Remove old chunks for this file
                old_chunk_ids_to_remove = [chunk_id for chunk_id, chunk in chunks.items() if chunk['file'] == str(file_path)]
                for chunk_id in old_chunk_ids_to_remove:
                    del chunks[chunk_id]

                # Get new file metadata
                file_metadata = self.get_file_metadata(file_path)
                new_file_metadata[str(file_path)] = file_metadata

                # Create new chunks for this file
                file_chunks = self.get_file_chunks(file_path, file_metadata['hash'])
                for chunk in file_chunks:
                    chunks[chunk['id']] = chunk

        print(f"Total chunks after update: {len(chunks)}")

        # * Incrementally update the FAISS index
        if changed_files or deleted_files:
            index = self.update_faiss_index_incrementally(existing_index, chunks, changed_files, deleted_files)
        else:
            index = existing_index

        if index is None:
            return

        # Save everything
        index_dir = self.rag_dir / language_extension
        index_dir.mkdir(exist_ok=True, parents=True)

        with Timer("Save FAISS index"):
            faiss.write_index(index, str(index_dir / "vectors.index"))

        with Timer("Save chunks"):
            chunks_list = list(chunks.values())
            # Sort by chunk ID for consistent ordering
            chunks_list.sort(key=lambda x: x['id'])
            with open(index_dir / "chunks.json", 'w') as f:
                json.dump(chunks_list, f, indent=2)

        with Timer("Save file metadata"):
            with open(index_dir / "files.json", 'w') as f:
                json.dump(new_file_metadata, f, indent=2)

        print(f"[green]Index updated successfully!")
        if changed_files:
            print(f"[green]Processed {len(changed_files)} changed files")
        if deleted_files:
            print(f"[green]Removed {len(deleted_files)} deleted files")

def trash_indexes(rag_dir, language_extension="lua"):
    """Remove index for a specific language"""
    index_path = Path(rag_dir, language_extension)
    subprocess.run(["trash", index_path], check=IGNORE_FAILURE)

if __name__ == "__main__":
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
