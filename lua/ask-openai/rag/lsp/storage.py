from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
from typing import List, Optional, Protocol

# * TORCH BEFORE FAISS (even if don't need torch here/yet)
# model_qwen3/model_st (REMINDER when I go to rearrange again)
# import torch  # MUST be imported BEFORE FAISS else Qwen3 will explode on model import (can happen to other models too)
import faiss
# TODO OK SO ... the torch "fix" fubars the LS... GAH... get this print warning:
#   [START][2025-07-15 05:18:11] LSP logging initiated
# [ERROR][2025-07-15 05:18:11] ...p/_transport.lua:36	"rpc"	"/Users/wesdemos/repos/github/g0t4/ask-openai.nvim/.venv/bin/python"	"stderr"	"/opt/homebrew/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/lib/python3.13/multiprocessing/resource_tracker.py:301: UserWarning: resource_tracker: There appear to be 1 leaked semaphore objects to clean up at shutdown: {'/loky-62322-yvt4wtp_'}\n  warnings.warn(\n"
#  CAN I GET THE GODDAMN THING TO STOP PRINTING MESSAGES? why does it have a lot and still print?
#   is it the print that kills this OR is that print just happening after the actual issue
#   FUUUU MULTITASKING... smth
#    LATER!
#     I SUGGEST LOOK AT THE REAL ISSUE WITH FAISS/TORCH import order ... smells like BS that I should have to put one ahead of the other

import numpy as np
from pydantic import BaseModel

from .logs import get_logger
from lsp import fs

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
    id_int: str  # mostly store this for comparing manually (when reviewing the files themselves)
    text: str
    file: str
    start_line: int
    end_line: int
    type: str
    file_hash: str

    @property
    def faiss_id(self):
        # return int(self.id_int)
        # for now just recompute and skip id_int:
        return chunk_id_to_faiss_id(self.id)

# * FAISS type hint wrappers
class Int64VectorIndex(Protocol):
    """ Type hint wrapper for FAISS/swigfaiss runtime types so I can get some decent completions in dev """

    def __len__(self) -> int:
        ...

class FaissIndexView:
    """ Concrete wrapper around faiss index type, provide better typing AND hide inner workings"""

    def __init__(self, dataset: "RAGDataset"):
        self.dataset = dataset

    def num_vectors(self) -> int:
        return self.dataset.index.ntotal

    @property
    def _id_map(self) -> Int64VectorIndex:
        # under the hood: <class 'faiss.swigfaiss.Int64Vector'>
        # PRN can I hide this and just rely on ids?
        return self.dataset.index.id_map

    @property
    def ids(self):
        return faiss.vector_to_array(self._id_map)

@dataclass
class RAGDataset:

    def __init__(self, language_extension, chunks_by_file, files_by_path, index):
        self.language_extension = language_extension
        self.chunks_by_file = chunks_by_file
        self.stat_by_path = files_by_path
        self.index = index
        self.index_view = FaissIndexView(self)

    language_extension: str
    chunks_by_file: dict[str, List[Chunk]]
    stat_by_path: dict[str, FileStat]
    index: faiss.Index
    index_view: FaissIndexView

@dataclass
class Datasets:
    all_datasets: dict[str, RAGDataset]
    # FYI must use default_factory else the default dict {} is shared among all instances! b/c defaults are evaluated ONCE in scope that declares this class
    _chunks_by_faiss_id: dict[int, Chunk] = field(default_factory=dict)

    def __post_init__(self):
        for dataset in self.all_datasets.values():
            for _, chunks in dataset.chunks_by_file.items():
                for chunk in chunks:
                    faiss_id = chunk.faiss_id
                    self._chunks_by_faiss_id[faiss_id] = chunk

    def get_chunk_by_faiss_id(self, faiss_id) -> Optional[Chunk]:
        # now consumers have no knowledge of the cache
        #  this will help with updates too, to not let the updater have to think about this
        # FYI I don't have to remove items here b/c they are content hashed so doesn't matter if they're left behind (for now)
        # PRN might wanna move this to the dataset level to update it on updates to a doc in a dataset
        return self._chunks_by_faiss_id.get(faiss_id)

    def for_file(self, file_path: str | Path, vim_filetype: str | None = None):
        language_extension = Path(file_path).suffix.removeprefix('.') or vim_filetype
        if language_extension == '' or language_extension is None:
            logger.error("No file suffix and no vim_filetype, can't find dataset!")
            return None

        return self.all_datasets.get(language_extension)

    def update_file(self, file_path_str: str | Path, new_chunks: List[Chunk], model_wrapper):
        file_path_str = str(file_path_str)  # must be str, just let people pass either

        dataset = self.for_file(file_path_str)
        if dataset is None:
            logger.error(f"No dataset for path: {file_path_str}")
            # TODO should I create it then (from scratch) as first file?
            return

        if dataset.index is None:
            logger.error(f"Dataset {dataset.language_extension} has no index")
            # TODO should I be creating it in this case?
            #    ADD TESTS FOR THIS
            return

        # * find prior chunks (if any)
        prior_chunks: list[Chunk] | None = None
        if file_path_str in dataset.chunks_by_file:
            logger.debug(f"Prior chunks exist for {fs.get_loggable_path(file_path_str)}")
            prior_chunks = dataset.chunks_by_file[file_path_str]

        if not prior_chunks:
            logger.debug(f"No prior_chunks")
            prior_chunks = []

        # * FAISS UPDATES:
        new_faiss_ids = [c.faiss_id for c in new_chunks]
        prior_faiss_ids = [c.faiss_id for c in prior_chunks]

        # * YES! if chunks match, skip encoding which is most expensive part!
        if prior_faiss_ids == new_faiss_ids:
            logger.debug(f"prior_chunks match new_chunks, SKIP re-encoding!")
            return

        # * useful troubleshooting when rebuilding (won't need this if chunks match)
        logger.pp_debug("prior_chunks", prior_chunks)
        logger.pp_debug("new_chunks", new_chunks)
        logger.pp_debug("new_faiss_ids", new_faiss_ids)
        logger.pp_debug("prior_faiss_ids", prior_faiss_ids)

        prior_selector = faiss.IDSelectorArray(np.array(prior_faiss_ids, dtype="int64"))
        dataset.index.remove_ids(prior_selector)

        with logger.timer("Encode new vectors"):
            passages = [chunk.text for chunk in new_chunks]
            vecs_np = model_wrapper.encode_passages(passages)

        faiss_ids_np = np.array(new_faiss_ids, dtype="int64")

        dataset.index.add_with_ids(vecs_np, faiss_ids_np)

        # * update file's list of chunks
        dataset.chunks_by_file[file_path_str] = new_chunks

        # # * updates for cache in  _chunks_by_faiss_id
        for prior_id in prior_faiss_ids:
            del self._chunks_by_faiss_id[prior_id]
        for new_chunk in new_chunks:
            self._chunks_by_faiss_id[new_chunk.faiss_id] = new_chunk

def load_chunks(chunks_json_path: Path):
    with open(chunks_json_path, 'r') as f:
        chunks_by_file = {k: [Chunk(**v) for v in v] for k, v in json.load(f).items()}
    return chunks_by_file

def load_prior_data(dot_rag_dir: Path, language_extension: str) -> RAGDataset:
    language_dir = dot_rag_dir / language_extension

    vectors_index_path = language_dir / "vectors.index"
    index = None
    if vectors_index_path.exists():
        try:
            index = faiss.read_index(str(vectors_index_path))
        except Exception as e:
            logger.exception("Warning: Could not load existing index")
    else:
        logger.info(f"No vectors.index: {vectors_index_path}")

    chunks_json_path = language_dir / "chunks.json"
    chunks_by_file: dict[str, List[Chunk]] = {}

    if chunks_json_path.exists():
        try:
            chunks_by_file = load_chunks(chunks_json_path)
        except Exception as e:
            logger.exception(f"Warning: Could not load existing chunks: {e}")
    else:
        logger.info(f"No chunks.json: {chunks_json_path}")

    files_json_path = language_dir / "files.json"
    files_by_path = {}
    if files_json_path.exists():
        try:
            with open(files_json_path, 'r') as f:
                files_by_path = {k: FileStat(**v) for k, v in json.load(f).items()}
        except Exception as e:
            logger.exception(f"Warning: Could not load file stats {e}")
    else:
        logger.info(f"No files.json: {files_json_path}")

    if logger.isEnabledForInfo():
        # don't spend time if not gonna log it
        num_chunks = sum(len(v) for v in chunks_by_file.values())
        log_num_vectors = index.ntotal if index is not None else None
        logger.info(f"Loaded {language_extension} - {len(files_by_path)} file stats, {log_num_vectors} FAISS vectors, {num_chunks} chunks")

    return RAGDataset(language_extension, chunks_by_file, files_by_path, index)

def find_language_dirs(dot_rag_dir: Path) -> List[Path]:
    dot_rag_dir = Path(dot_rag_dir)
    if not dot_rag_dir.exists():
        raise ValueError(f"{dot_rag_dir=} does not exist")
    if not dot_rag_dir.is_dir():
        raise ValueError(f"{dot_rag_dir=} is not a directory")

    return [p for p in Path(dot_rag_dir).glob("*") if p.is_dir()]

def load_all_datasets(dot_rag_dir: Path) -> Datasets:
    dot_rag_dir = Path(dot_rag_dir)
    language_dirs = find_language_dirs(dot_rag_dir)
    datasets = {}
    for lang_dir in language_dirs:
        language_extension = lang_dir.name
        dataset = load_prior_data(dot_rag_dir, language_extension)
        datasets[language_extension] = dataset

    return Datasets(datasets)
