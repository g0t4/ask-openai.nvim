from pydantic import BaseModel
from pathlib import Path
import json

class FileStat(BaseModel):
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

def load_chunks(chunks_json_path: Path):
    with open(chunks_json_path, 'r') as f:
        chunks_by_file = {k: [Chunk(**v) for v in v] for k, v in json.load(f).items()}
    return chunks_by_file
