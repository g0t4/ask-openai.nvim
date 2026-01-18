import os
from pathlib import Path
from transformers import AutoTokenizer

os.environ["TRANSFORMERS_OFFLINE"] = "1"
# TODO FOR NOW use estimate of tokens and ONLY ever use tokenizer if a node is way past estimate
#  9 tokens per line is my measurement in some files
#  3.6 characters per token?

# Qwen3 embedding model (same tokenizer as Qwen3 proper)
model_id = "Qwen/Qwen3-Embedding-0.6B"
tokenizer = AutoTokenizer.from_pretrained(
    model_id,
    local_files_only=True,
    use_fast=True,
)

def count_tokens(text: str) -> int:
    # returns token count
    return len(tokenizer.encode(text))

def tokenize(text: str):
    # returns list of token IDs
    return tokenizer.encode(text)

if __name__ == "__main__":
    file = Path(__file__).parent.parent.parent / "indexer.py"
    sample = file.read_text()
    # ids = tokenize(sample)
    # print("Token IDs:", ids)
    print("Token count:", count_tokens(sample))
