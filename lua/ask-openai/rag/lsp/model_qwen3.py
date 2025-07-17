import os

from .logs import get_logger

logger = get_logger(__name__)

# FYI there is a test case to validate encoding:
#   python3 indexer_tests.py  TestBuildIndex.test_encode_and_search_index

_model = None

def ensure_model_loaded():
    global _model
    if _model:
        return _model

    with logger.timer("import transformers qwen3"):

        # do not check hugging face for newer version, use offline cache only
        #   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
        # FYI must be set BEFORE importing SentenceTransformer, setting after (even if before model load) doesn't work
        os.environ["TRANSFORMERS_OFFLINE"] = "1"

        from lsp.notes import transformers_qwen3

    _model = transformers_qwen3
    return _model

def _encode(texts):
    import torch
    import numpy as np

    # set batch_size high to disable batching if that is better perf on the 5090s
    #   added batching to investigate issues w/ qwen3 on mac w/ ST and the memory explosion (even after disable autograd!)
    def batched_encode(texts, batch_size=8):
        all_vecs = []
        with torch.no_grad():
            total = len(texts)
            for i in range(0, total, batch_size):
                logger.info(f"    batch {i}-{i+batch_size} of {total}")
                batch = texts[i:i + batch_size]
                vecs = ensure_model_loaded().encode(batch)
                all_vecs.append(vecs)

        return np.concatenate(all_vecs)

    vecs_np = batched_encode(texts)
    return vecs_np

def encode_passages(passages: list[str]):
    texts = [f"passage: {p}" for p in passages]
    return _encode(texts)

def encode_query(text: str):
    # "query: text" is the training query format
    # "passage: text" is the training document format
    return _encode_text(f"query: {text}")

def _encode_text(text: str):
    return _encode([text])

def get_shape() -> int:
    # Create a dummy vector to get dimensions
    sample_text = "passage: sample"
    sample_vec = _encode_text(sample_text)
    shape = sample_vec.shape[1]
    return shape
