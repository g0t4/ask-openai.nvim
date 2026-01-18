import os

import indexer
from indexer import IncrementalRAGIndexer
import lsp.inference.server.qwen3_embeddings as qwen3_embeddings
from lsp.logs import *
import qwen3_embeddings

# logger = get_logger(__name__)
# logging_fwk_to_console("INFO")

def read_file_next_to_me(filename):
    current_dir = os.path.dirname(os.path.abspath(qwen3_embeddings.__file__))
    file_path = os.path.join(current_dir, filename)
    with open(file_path, 'r') as f:
        return f.read()

content = ''.join(read_file_next_to_me(filename) for filename in ['qwen3_embeddings.py', 'helpers.py', '__main__.py', 'qwen3_rerank.py'])

print(len(content))

# Split content into 10 chunks
chunk_size = len(content) // 10
chunks = [content[i:i + chunk_size] for i in range(0, len(content), chunk_size)]

# Process each chunk separately
results = []
# for iteration in range(100):
# print(f"Outer loop iteration {iteration + 1}")
for i, chunk in enumerate(chunks):
    print(f"Processing chunk {i+1}")
    result = qwen3_embeddings.encode([chunk])
    results.append(result)

print("All chunks processed")
