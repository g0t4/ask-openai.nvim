import json
import hashlib
from pathlib import Path
import subprocess
from typing import Dict, List, Set, Tuple, Optional
import os

import faiss
import numpy as np
from rich import print

from timing import Timer

# constants for subprocess.run for readability
IGNORE_FAILURE = False
STOP_ON_FAILURE = True

with Timer("Build RAG index"):
    from sentence_transformers import SentenceTransformer

rag_dir = "./tmp/rag_index"
model_name = "intfloat/e5-base-v2"
with Timer(f"Load model {model_name}"):
    model = SentenceTransformer(model_name)


class IncrementalRAGIndexer:
    def __init__(self, rag_dir: str = "./tmp/rag_index", model_name: str = "intfloat/e5-base-v2"):
        self.rag_dir = Path(rag_dir)
        self.model_name = model_name
        self.model = model  # Use the globally loaded model
        
    def get_file_hash(self, file_path: Path) -> str:
        """Get SHA256 hash of file contents"""
        hasher = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    
    def get_file_metadata(self, file_path: Path) -> Dict:
        """Get file metadata (hash, mtime, size)"""
        stat = file_path.stat()
        return {
            'path': str(file_path),
            'hash': self.get_file_hash(file_path),
            'mtime': stat.st_mtime,
            'size': stat.st_size
        }
    
    def generate_chunk_id(self, file_path: Path, chunk_index: int, file_hash: str) -> str:
        """Generate unique chunk ID based on file path, chunk index, and file hash"""
        chunk_str = f"{file_path}:{chunk_index}:{file_hash}"
        return hashlib.sha256(chunk_str.encode()).hexdigest()[:16]
    
    def simple_chunk_file(self, path: Path, file_hash: str, lines_per_chunk: int = 20, overlap: int = 5) -> List[Dict]:
        """Chunk a file with unique chunk IDs"""
        chunks = []
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
            
        for i in range(0, len(lines), lines_per_chunk - overlap):
            chunk_lines = lines[i:i + lines_per_chunk]
            text = "".join(chunk_lines).strip()
            if text:
                chunk_id = self.generate_chunk_id(path, i, file_hash)
                chunks.append({
                    "id": chunk_id,
                    "text": text,
                    "file": str(path),
                    "start_line": i + 1,
                    "end_line": i + len(chunk_lines),
                    "type": "raw",
                    "file_hash": file_hash
                })
        return chunks
    
    def find_files_with_fd(self, source_dir: str, language_extension: str) -> List[Path]:
        """Find files using fd command"""
        result = subprocess.run(
            ["fd", f".*\\.{language_extension}$", source_dir, "--absolute-path", "--type", "f"],
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        return [Path(line) for line in result.stdout.strip().splitlines()]
    
    def load_existing_index(self, language_extension: str) -> Tuple[Optional[faiss.Index], Dict, Dict]:
        """Load existing index, chunks, and file metadata"""
        index_dir = self.rag_dir / language_extension
        
        # Load FAISS index
        index_path = index_dir / "vectors.index"
        index = None
        if index_path.exists():
            try:
                index = faiss.read_index(str(index_path))
                print(f"Loaded existing FAISS index with {index.ntotal} vectors")
            except Exception as e:
                print(f"[yellow]Warning: Could not load existing index: {e}")
        
        # Load chunks
        chunks_path = index_dir / "chunks.json"
        chunks = {}
        if chunks_path.exists():
            try:
                with open(chunks_path, 'r') as f:
                    chunks_list = json.load(f)
                    chunks = {chunk['id']: chunk for chunk in chunks_list}
                print(f"Loaded {len(chunks)} existing chunks")
            except Exception as e:
                print(f"[yellow]Warning: Could not load existing chunks: {e}")
        
        # Load file metadata
        metadata_path = index_dir / "file_metadata.json"
        file_metadata = {}
        if metadata_path.exists():
            try:
                with open(metadata_path, 'r') as f:
                    file_metadata = json.load(f)
                print(f"Loaded metadata for {len(file_metadata)} files")
            except Exception as e:
                print(f"[yellow]Warning: Could not load file metadata: {e}")
        
        return index, chunks, file_metadata
    
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
    
    def remove_chunks_for_files(self, chunks: Dict, deleted_files: Set[str]) -> Dict:
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
    
    def rebuild_faiss_index(self, chunks: Dict) -> faiss.Index:
        """Rebuild FAISS index from scratch using current chunks"""
        if not chunks:
            print("[yellow]No chunks to index")
            return None
        
        print(f"Rebuilding FAISS index with {len(chunks)} chunks")
        
        # Get texts in consistent order (sorted by chunk ID for reproducibility)
        sorted_chunks = sorted(chunks.items())
        texts = [f"passage: {chunk['text']}" for _, chunk in sorted_chunks]
        
        with Timer("Encode texts to vectors"):
            vecs = self.model.encode(texts, normalize_embeddings=True, show_progress_bar=True)
        
        vecs_np = np.array(vecs).astype("float32")
        
        with Timer("Build FAISS index"):
            index = faiss.IndexFlatIP(vecs_np.shape[1])
            index.add(vecs_np)
        
        return index
    
    def build_index(self, source_dir: str = ".", language_extension: str = "lua"):
        """Build or update the RAG index incrementally"""
        print(f"[bold]Building/updating {language_extension} RAG index:")
        
        # Load existing data
        existing_index, existing_chunks, existing_file_metadata = self.load_existing_index(language_extension)
        
        # Find current files
        with Timer("Find files"):
            current_files = self.find_files_with_fd(source_dir, language_extension)
            print(f"Found {len(current_files)} {language_extension} files")
        
        if not current_files:
            print("[red]No files found, no index to build")
            return
        
        # Find changed and deleted files
        changed_files, deleted_files = self.find_changed_files(current_files, existing_file_metadata)
        
        if not changed_files and not deleted_files:
            print("[green]No changes detected, index is up to date!")
            return
        
        print(f"Processing {len(changed_files)} changed files")
        
        # Start with existing chunks and remove deleted files
        chunks = self.remove_chunks_for_files(existing_chunks, deleted_files)
        
        # Process changed files
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
                old_chunks_to_remove = [
                    chunk_id for chunk_id, chunk in chunks.items() 
                    if chunk['file'] == str(file_path)
                ]
                for chunk_id in old_chunks_to_remove:
                    del chunks[chunk_id]
                
                # Get new file metadata
                file_metadata = self.get_file_metadata(file_path)
                new_file_metadata[str(file_path)] = file_metadata
                
                # Create new chunks for this file
                file_chunks = self.simple_chunk_file(file_path, file_metadata['hash'])
                for chunk in file_chunks:
                    chunks[chunk['id']] = chunk
        
        print(f"Total chunks after update: {len(chunks)}")
        
        # Always rebuild the FAISS index (needed because we can't easily remove vectors)
        # For very large indexes, you might want to implement a more sophisticated approach
        index = self.rebuild_faiss_index(chunks)
        
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
            with open(index_dir / "file_metadata.json", 'w') as f:
                json.dump(new_file_metadata, f, indent=2)
        
        print(f"[green]Index updated successfully!")
        if changed_files:
            print(f"[green]Processed {len(changed_files)} changed files")
        if deleted_files:
            print(f"[green]Removed {len(deleted_files)} deleted files")


def build_index(source_dir=".", language_extension="lua"):
    """Legacy function wrapper for backward compatibility"""
    indexer = IncrementalRAGIndexer(rag_dir)
    indexer.build_index(source_dir, language_extension)


def trash_indexes(language_extension="lua"):
    """Remove index for a specific language"""
    index_path = Path(rag_dir, language_extension)
    subprocess.run(["trash", index_path], check=IGNORE_FAILURE)


if __name__ == "__main__":
    with Timer("Total indexing time"):
        indexer = IncrementalRAGIndexer(rag_dir)
        indexer.build_index(language_extension="lua")
        indexer.build_index(language_extension="py") 
        indexer.build_index(language_extension="fish")
