from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
from typing import List, Optional

import faiss
from pydantic import BaseModel
from .logs import get_logger

logger = get_logger(__name__)

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

@dataclass
class Datasets:
    all_datasets: dict[str, RAGDataset]
    # FYI must use default_factory else the default dict {} is shared among all instances! b/c defaults are evaluated ONCE in scope that declares this class
    _chunks_by_faiss_id: dict[int, Chunk] = field(default_factory=dict)

    def __post_init__(self):
        for dataset in self.all_datasets.values():
            for _, chunks in dataset.chunks_by_file.items():
                for chunk in chunks:
                    faiss_id = chunk.faiss_id()
                    self._chunks_by_faiss_id[faiss_id] = chunk

    def get_chunk_by_faiss_id(self, faiss_id) -> Optional[Chunk]:
        # now consumers have no knowledge of the cache
        #  this will help with updates too, to not let the updater have to think about this
        # FYI I don't have to remove items here b/c they are content hashed so doesn't matter if they're left behind (for now)
        # PRN might wanna move this to the dataset level to update it on updates to a doc in a dataset
        return self._chunks_by_faiss_id.get(faiss_id)

    def for_file(self, file_path: str | Path):
        language_extension = Path(file_path).suffix.removeprefix('.')
        return self.all_datasets.get(language_extension)

    # def _delete_file(self, file_path: str | Path):
    #     # TODO! with update_file
    #     pass

    def update_file(self, file_path: str | Path, file_hash: str, new_chunks: List[Chunk]):
        dataset = self.for_file(file_path)
        if dataset is None:
            logger.info(f"No dataset for path: {file_path}")
            return

        # TODO pass or hardcode chunk_type?
        # TODO do I need to pass file_hash? IIAC I won't
        # FYI first pass is ONLY to get this to work for LS client...
        #    FYI NOT to prepare to port indexer to use this!
        #    make this specific to just the use case of LS update_file
        #    that means no need for stat (stat only used by indexer to see what changed between its bulk updates)
        # TODO call self._delete_file?

        # * find prior chunks (if any)
        prior_chunks = None
        if file_path in dataset.chunks_by_file:
            prior_chunks = dataset.chunks_by_file[str(file_path)]

        if not prior_chunks:
            logger.info(f"No prior_chunks")

        logger.info(f"Updating {file_path}")
        logger.pp_info("prior_chunks", prior_chunks)

        # dataset.chunks_by_file[path] = new_chunks

def load_chunks(chunks_json_path: Path):
    with open(chunks_json_path, 'r') as f:
        chunks_by_file = {k: [Chunk(**v) for v in v] for k, v in json.load(f).items()}
    return chunks_by_file

def load_prior_data(language_extension: str, language_dir: Path) -> RAGDataset:

    vectors_index_path = language_dir / "vectors.index"
    index = None
    if vectors_index_path.exists():
        try:
            index = faiss.read_index(str(vectors_index_path))
            print(f"Loaded existing FAISS index with {index.ntotal} vectors")
        except Exception as e:
            print(f"[yellow]Warning: Could not load existing index: {e}")

    chunks_json_path = language_dir / "chunks.json"
    chunks_by_file: dict[str, List[Chunk]] = {}

    if chunks_json_path.exists():
        try:
            chunks_by_file = load_chunks(chunks_json_path)
            print(f"Loaded {len(chunks_by_file)} existing chunks")
        except Exception as e:
            print(f"[yellow]Warning: Could not load existing chunks: {e}")

    files_json_path = language_dir / "files.json"
    files_by_path = {}
    if files_json_path.exists():
        try:
            with open(files_json_path, 'r') as f:
                files_by_path = {k: FileStat(**v) for k, v in json.load(f).items()}
            print(f"Loaded stats for {len(files_by_path)} files")
        except Exception as e:
            print(f"[yellow]Warning: Could not load file stats {e}")

    return RAGDataset(language_extension, chunks_by_file, files_by_path, index)

def find_language_dirs(dot_rag_dir: str | Path):
    dot_rag_dir = Path(dot_rag_dir)
    if not dot_rag_dir.exists():
        raise ValueError(f"{dot_rag_dir=} does not exist")
    if not dot_rag_dir.is_dir():
        raise ValueError(f"{dot_rag_dir=} is not a directory")

    return [p for p in Path(dot_rag_dir).glob("*") if p.is_dir()]

def load_all_datasets(dot_rag_dir: str | Path) -> Datasets:
    dirs = find_language_dirs(dot_rag_dir)
    datasets = {}
    for dir_path in dirs:
        language_extension = dir_path.name
        dataset = load_prior_data(language_extension, dir_path)
        datasets[language_extension] = dataset
        logger.info(f"[green]Loaded {language_extension} with {len(dataset.chunks_by_file)} files")

    return Datasets(datasets)
