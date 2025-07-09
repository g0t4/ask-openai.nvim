import hashlib
import json
from pathlib import Path

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

def load_chunks(chunks_json_path: Path):
    with open(chunks_json_path, 'r') as f:
        chunks_by_file = {k: [Chunk(**v) for v in v] for k, v in json.load(f).items()}
    return chunks_by_file
