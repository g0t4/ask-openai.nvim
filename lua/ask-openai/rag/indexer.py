import json
from pathlib import Path
import subprocess

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

def simple_chunk_file(path, lines_per_chunk=20, overlap=5):
    chunks = []
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    for i in range(0, len(lines), lines_per_chunk - overlap):
        chunk_lines = lines[i:i + lines_per_chunk]
        text = "".join(chunk_lines).strip()
        if text:
            chunks.append({
                "text": text,
                "file": str(path),
                "start_line": i + 1,
                "end_line": i + len(chunk_lines),
                "type": "raw",
            })
    return chunks

def find_files_with_fd(source_dir: str, language_extension: str) -> list[Path]:
    result = subprocess.run(
        ["fd", f".*\\.{language_extension}$", source_dir, "--absolute-path", "--type", "f"],
        stdout=subprocess.PIPE,
        text=True,
        check=True,
    )
    return [Path(line) for line in result.stdout.strip().splitlines()]

def build_index(source_dir=".", language_extension="lua"):
    print(f"[bold]Building {language_extension} RAG index:")

    chunks = []

    with Timer("Find files"):
        files = find_files_with_fd(source_dir, language_extension)
        print(f"Found {len(files)} {language_extension} files")
        print(files)

    with Timer("Chunk files"):
        for i, file in enumerate(files):
            if i % 50 == 0 and i > 0:  # Progress update every 50 files
                print(f"Processed {i}/{len(files)} files...")

            file_chunks = simple_chunk_file(file)
            chunks.extend(file_chunks)

    print(f"Created {len(chunks)} total chunks")

    texts = [f"passage: {c['text']}" for c in chunks]

    with Timer("Encode texts to vectors"):
        vecs = model.encode(texts, normalize_embeddings=True, show_progress_bar=True)

    vecs_np = np.array(vecs).astype("float32")

    with Timer("Build FAISS index"):
        index = faiss.IndexFlatIP(vecs_np.shape[1])
        index.add(vecs_np)

    out_dir = Path(rag_dir, language_extension)
    Path(out_dir).mkdir(exist_ok=True, parents=True)

    with Timer("Write vectors.index"):
        faiss.write_index(index, f"{out_dir}/vectors.index")

    with Timer("Write chunks.json"):
        with open(f"{out_dir}/chunks.json", "w") as f:
            json.dump(chunks, f, indent=2)

def trash_indexes(language_extension="lua"):
    index_path = Path(rag_dir, language_extension)
    subprocess.run(["trash", index_path], check=IGNORE_FAILURE)

if __name__ == "__main__":
    with Timer("Total indexing time"):
        trash_indexes()
        build_index(language_extension="lua")
        build_index(language_extension="py")
