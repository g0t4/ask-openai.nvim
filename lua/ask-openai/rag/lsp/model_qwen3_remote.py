from .logs import get_logger

logger = get_logger(__name__)

_model = None

def ensure_model_loaded():
    global _model
    if _model:
        return _model

    with logger.timer("imports for qwen3 remote EmbedClient"):
        import numpy as np
        from lsp.remote.comms import EmbedClient

    # FYI client opens a socket so still useful to defer until needed
    _model = EmbedClient()
    return _model

def _encode(texts):
    import numpy as np

    def batched_encode(texts, batch_size=8):
        all_vecs = []
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
