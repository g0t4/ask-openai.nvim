from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
from typing import List, Optional

import faiss
from pydantic import BaseModel

def chunk_id_for(file_path: Path, chunk_type: str, start_line: int, end_line: int, file_hash: str) -> str:
    """Generate unique chunk ID based on file path, chunk index, and file hash"""
    chunk_str = f"{file_path}:{chunk_type}:{start_line}-{end_line}:{file_hash}"
    return hashlib.sha256(chunk_str.encode()).hexdigest()[:16]

def chunk_id_to_faiss_id(chunk_id: str) -> int:
    """Convert chunk ID to FAISS ID (signed int64)"""
    # Convert hex string directly to int and mask for signed int64
    hash_int = int(chunk_id, 16)
    # Mask to fit in signed int64 (0x7FFFFFFFFFFFFFFF = 2^63 - 1)
    return hash_int & 0x7FFFFFFFFFFFFFFF

class FileStat(BaseModel):
    mtime: float
    size: int
    hash: str
    path: str

class Chunk(BaseModel):
    id: str
    id_int: str  # mostly store this for comparing manually
    text: str
    file: str
    start_line: int
    end_line: int
    type: str
    file_hash: str

    def faiss_id(self):
        # TODO any issues with this?
        # return int(self.id_int)
        # for now just recompute and skip id_int:
        return chunk_id_to_faiss_id(self.id)

@dataclass
class RAGDataset:
    language_extension: str
    chunks_by_file: dict[str, List[Chunk]]
    stat_by_path: dict[str, FileStat]
    index: Optional[faiss.Index] = None

def load_chunks(chunks_json_path: Path):
    with open(chunks_json_path, 'r') as f:
        chunks_by_file = {k: [Chunk(**v) for v in v] for k, v in json.load(f).items()}
    return chunks_by_file

def load_prior_data(language_extension: str, rag_dir: Path) -> RAGDataset:
    index_dir = rag_dir / language_extension

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

    return RAGDataset(language_extension, chunks_by_file, files_by_path, index)

def find_language_dirs(rag_dir: str | Path):
    rag_dir = Path(rag_dir)
    if not rag_dir.exists():
        raise ValueError(f"{rag_dir=} does not exist")
    if not rag_dir.is_dir():
        raise ValueError(f"{rag_dir=} is not a directory")

    return [p for p in Path(rag_dir).glob("*") if p.is_dir()]

def load_all_rag_datasets(rag_dir: str | Path):
    dirs = find_language_dirs(rag_dir)
    datasets = {}
    for dir_path in dirs:
        language_extension = dir_path.name
        dataset = load_prior_data(language_extension, dir_path)
        datasets[language_extension] = dataset
    return datasets
