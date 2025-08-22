from .logs import get_logger
from .qwen3 import known

# FYI! IIRC this is the most recent alterantive to model_qwen3 in-process and model_st w/ intfloat/qwen3 via SentenceTransformers

logger = get_logger(__name__)

def todo_remove_this_eager_load_imports():

    with logger.timer("imports for qwen3 remote InferenceClient"):
        import numpy as np

    # FYI client opens a socket so still useful to defer until needed

def _encode_multiple(texts):
    import numpy as np
    from lsp.inference.client import InferenceClient

    # FYI for now lets leave batch_size at 8?
    # TODO capture some sequence length distribution data so I can see how variable it is
    #   and if small batch size would help to avoid padding for longest sequence in a bigger batch?
    def batched_encode(texts, batch_size=8):
        # PRN? allow multiple encodes per connection! right now server closes after one!
        # can add longer-lived connection (beyond this batch)
        #   BUT only if timing shows its worthwhile
        #   btw ok to let client complete an entire batch, that won't require server to handle multiple connections
        #     only need multi connection handling IF I allow longer-lived connections (like for entire life of LS/indexer)
        all_vecs = []
        total = len(texts)
        for i in range(0, total, batch_size):
            # FYI right now this is a new connection PER batch
            with InferenceClient() as client:
                logger.info(f"    batch {i}-{i+batch_size} of {total}")
                batch = texts[i:i + batch_size]
                vecs = client.encode({"texts": batch})
                all_vecs.append(vecs)

        return np.concatenate(all_vecs)

    vecs_np = batched_encode(texts)
    return vecs_np

def encode_passages(passages: list[str]):
    # FYI Qwen3 has NO passage/document label, only query side has Query:/Instruct:
    return _encode_multiple(passages)

def encode_query(text: str, instruct: str):
    return _encode_one_text(qwen3_format_query(text, instruct))

def _encode_one_text(text: str):
    return _encode_multiple([text])

def qwen3_format_query(text: str, instruct: str) -> str:
    if instruct:
        return f'Instruct: {instruct}\nQuery:{text}'
    return f"Query: {text}"

def get_shape() -> int:
    # Create a dummy vector to get dimensions
    sample_text = "passage: sample"
    sample_vec = _encode_one_text(sample_text)
    shape = sample_vec.shape[1]
    return shape
