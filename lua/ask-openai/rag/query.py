import faiss
import json
import numpy as np
from sentence_transformers import SentenceTransformer

def query_index(query, index_path="./tmp/rag_index/vectors.index", chunks_path="rag_index/chunks.json", top_k=3, model_name="intfloat/e5-base-v2"):
    index = faiss.read_index(index_path)
    with open(chunks_path) as f:
        chunks = json.load(f)

    model = SentenceTransformer(model_name)
    q_vec = model.encode([f"query: {query}"], normalize_embeddings=True).astype("float32")
    scores, ids = index.search(q_vec, top_k)

    print("\nTop Matches:")
    for rank, idx in enumerate(ids[0]):
        c = chunks[idx]
        print(f"#{rank+1} ({scores[0][rank]:.3f}) {c['file']}:{c['start_line']}")
        print(c['text'])
        print("-" * 40)

if __name__ == "__main__":
    query_index("function that parses JSON in Lua")

