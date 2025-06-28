import faiss
import json
import numpy as np
from pathlib import Path
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
                "type": "raw"
            })
    return chunks

def build_index(source_dir=".", out_dir="./tmp/rag_index", model_name="intfloat/e5-base-v2"):
    model = SentenceTransformer(model_name)
    chunks = []
    for file in Path(source_dir).rglob("*.lua"):
        chunks.extend(simple_chunk_file(file))

    texts = [f"passage: {c['text']}" for c in chunks]
    vecs = model.encode(texts, normalize_embeddings=True)
    vecs_np = np.array(vecs).astype("float32")

    index = faiss.IndexFlatIP(vecs_np.shape[1])
    index.add(vecs_np)

    Path(out_dir).mkdir(exist_ok=True)
    faiss.write_index(index, f"{out_dir}/vectors.index")
    with open(f"{out_dir}/chunks.json", "w") as f:
        json.dump(chunks, f, indent=2)

    print(f"Indexed {len(chunks)} chunks.")

if __name__ == "__main__":
    build_index()

