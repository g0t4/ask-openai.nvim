"""
Utility to index and query directories in `$HOME/repos`
- idea is... what if I had a semantic_cd ... basically let me cd to a dir by describing what I want to jump to instead of a path?

FYI!!! this was a VERY ABUSIVE build out using gptoss and then wes hacking around a bit too... mostly gptoss
- gptoss did a damn good job given how shoddy my instructions were!
"""

import asyncio
import json
import os
import subprocess
from pathlib import Path
import sys
from typing import List, Dict

from lsp.inference.client.embedder import encode_passages
import faiss
import numpy as np

DEFAULT_ROOT = Path(os.getenv("HOME", "~")) / "repos"
OUTPUT_DIR = Path(os.getenv("HOME", "~")) / ".local/semantic_grep/dir"
OUTPUT_FILE = OUTPUT_DIR / "embeddings.json"
INDEX_FILE = OUTPUT_DIR / "index.faiss"

def get_directory_paths(root: Path) -> List[Path]:
    # PRN perhaps use the actual `z` fish function's store of recent directories as the source of directories to index instead of everything?
    #   /Users/wesdemos/.local/share/z/data
    #
    cmd = [
        "fd",
        ".",
        str(root),
        "--max-depth",
        # PRN relax the limit here on # dirs
        "5",
        "--type",
        "dir",
        "--absolute-path",
    ]
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    paths = [Path(p) for p in result.stdout.splitlines() if p]
    print(f"fd found {len(paths)} directories under {root}")
    return paths

async def _embed_files(paths: List[Path], batch_size: int = 16) -> Dict[Path, np.ndarray]:
    """Encode *paths* in batches and return a mapping Path -> vector (np.ndarray)."""
    embeddings: Dict[Path, np.ndarray] = {}
    total = len(paths)
    print(f"Embedding {total} directories in batches of {batch_size}")
    for i in range(0, total, batch_size):
        batch = paths[i:i + batch_size]
        texts: List[str] = []
        batch_paths: List[Path] = []
        for p in batch:
            # The path string itself is the content to embed
            texts.append(str(p))
            batch_paths.append(p)
        if not texts:
            continue
        print(f"Encoding batch {i // batch_size + 1}/{(total + batch_size - 1) // batch_size}")
        vecs_np = await encode_passages(texts)
        for path_obj, vec in zip(batch_paths, vecs_np):
            embeddings[path_obj] = vec
    return embeddings

async def build_index(root: Path = DEFAULT_ROOT) -> None:
    """Entry point: index *root* and store vectors in a Faiss index.

    The JSON file maps each absolute directory path to the integer Faiss ID that
    references its vector inside ``index.faiss``.
    """
    print(f"Starting indexing for root: {root}")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    paths = get_directory_paths(root)
    path_to_vec = await _embed_files(paths)

    # Build Faiss index (using inner product for cosine similarity)
    if not path_to_vec:
        print("No directories to index.")
        return
    sample_vec = next(iter(path_to_vec.values()))
    dim = sample_vec.shape[0]
    # Use an IndexIDMap wrapper so we can assign deterministic IDs with add_with_ids.
    # IndexFlatIP alone does not implement add_with_ids, which caused a RuntimeError.
    base_index = faiss.IndexFlatIP(dim)
    index = faiss.IndexIDMap(base_index)
    # Assign deterministic ids based on enumeration order
    ids: List[int] = []
    vectors: List[np.ndarray] = []
    path_id_map: Dict[str, int] = {}
    for idx, (path_obj, vec) in enumerate(path_to_vec.items()):
        faiss_id = idx + 1  # Faiss ids must be > 0
        ids.append(faiss_id)
        vectors.append(vec)
        path_id_map[str(path_obj)] = faiss_id
    vecs_np = np.vstack(vectors).astype("float32")
    ids_np = np.array(ids, dtype="int64")
    index.add_with_ids(vecs_np, ids_np)

    # Persist index and mapping
    faiss.write_index(index, str(INDEX_FILE))
    with OUTPUT_FILE.open("w", encoding="utf-8") as f:
        json.dump(path_id_map, f, ensure_ascii=False)
    print(f"Saved Faiss index to {INDEX_FILE} and mapping to {OUTPUT_FILE} (total {len(ids)} entries)")

async def query(query_text: str) -> None:
    """Search the Faiss index for *query_text* and print top matches.

    The function loads the path‑to‑id mapping from ``embeddings.json`` and the
    corresponding Faiss index from ``index.faiss``.
    """
    if not OUTPUT_FILE.exists() or not INDEX_FILE.exists():
        print("Index or mapping not found. Run the script without arguments first.")
        return
    # Load path -> id mapping
    with OUTPUT_FILE.open("r", encoding="utf-8") as f:
        path_id_map: Dict[str, int] = json.load(f)
    # Load Faiss index
    index = faiss.read_index(str(INDEX_FILE))
    # Ensure mapping and index sizes match
    assert len(path_id_map) == index.ntotal, f"embeddings.json count {len(path_id_map)} != faiss index count {index.ntotal}"
    # Build reverse lookup id -> path
    id_path_map = {int(v): k for k, v in path_id_map.items()}
    # Encode query
    query_vec_np = await encode_passages([query_text])
    query_vec = query_vec_np.astype("float32")
    top_n = 5
    distances, ids = index.search(query_vec, top_n)
    print(f"Top {top_n} results for query: '{query_text}'")
    for idx, distance in zip(ids[0], distances[0]):
        path = id_path_map.get(int(idx), "<unknown>")
        print(f"  {path} (score: {distance:.4f})")

if __name__ == "__main__":

    if len(sys.argv) < 2:
        print("Usage: python z.py [index|cd <query>]")
        sys.exit(1)

    subcommand = sys.argv[1]
    if subcommand == "index":
        asyncio.run(build_index())
    elif subcommand == "cd":
        query_text = " ".join(sys.argv[2:])
        asyncio.run(query(query_text))
    else:
        print(f"Unknown subcommand: {subcommand}")
        sys.exit(1)
