import faiss
import json
import numpy as np
from pathlib import Path
from timing import Timer

with Timer("Build RAG index"):
    from sentence_transformers import SentenceTransformer

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

def build_index(source_dir=".", out_dir="./tmp/rag_index", model_name="intfloat/e5-base-v2"):
    with Timer(f"Load model {model_name}"):
        model = SentenceTransformer(model_name)

    chunks = []

    with Timer("Find files"):
        lua_files = list(Path(source_dir).rglob("*.lua"))
        print(f"Found {len(lua_files)} .lua files")

    with Timer("Chunk files"):
        for i, file in enumerate(lua_files):
            if i % 50 == 0 and i > 0:  # Progress update every 50 files
                print(f"Processed {i}/{len(lua_files)} files...")

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

    Path(out_dir).mkdir(exist_ok=True)

    with Timer("Write vectors.index"):
        faiss.write_index(index, f"{out_dir}/vectors.index")

    with Timer("Write chunks.json"):
        with open(f"{out_dir}/chunks.json", "w") as f:
            json.dump(chunks, f, indent=2)

if __name__ == "__main__":
    with Timer("Total indexing time"):
        build_index()
