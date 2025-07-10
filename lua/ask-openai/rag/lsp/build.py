import hashlib
from pathlib import Path
from typing import Dict, List

from lsp.storage import Chunk, FileStat, chunk_id_for, chunk_id_to_faiss_id

def get_file_hash(file_path: Path | str) -> str:
    file_path = Path(file_path)
    # PRN is this slow? or ok?
    hasher = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def get_file_hash_from_lines(lines: list[str]) -> str:
    hasher = hashlib.sha256()
    # FYI lines have \n on end from LSP... so don't need to join w/ that between lines
    for line in lines:
        hasher.update(line.encode())
    return hasher.hexdigest()

def get_file_stat(file_path: Path | str) -> FileStat:
    file_path = Path(file_path)

    stat = file_path.stat()
    return FileStat(
        mtime=stat.st_mtime,
        size=stat.st_size,
        hash=get_file_hash(file_path),
        path=str(file_path)  # for serializing and reading by LSP
    )

def build_file_chunks(path: Path | str, file_hash: str, lines_per_chunk: int = 20, overlap: int = 5) -> List[Chunk]:
    path = Path(path)

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
        return build_from_lines(path, file_hash, lines, lines_per_chunk, overlap)

def build_from_lines(path: Path, file_hash: str, lines: List[str], \
                     lines_per_chunk: int = 20, overlap: int = 4)  -> List[Chunk]:

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
            chunk_id = chunk_id_for(path, chunk_type, start_line, end_line, file_hash)
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

    chunks = []
    for _, chunk in enumerate(iter_chunks(lines, lines_per_chunk, overlap)):
        chunks.append(chunk)

    return chunks
