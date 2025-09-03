from lsp.logs import get_logger
from typing import Optional

logger = get_logger(__name__)

async def _encode_batch(texts: list[str]) -> "np.ndarray":
    import numpy as np
    from lsp.inference.client import AsyncInferenceClient

    # FYI for now lets leave batch_size at 8?
    # TODO capture some sequence length distribution data so I can see how variable it is
    #   and if small batch size would help to avoid padding for longest sequence in a bigger batch?
    async def batched_encode(texts: list[str], batch_size: int = 8) -> np.ndarray:
        # PRN? allow multiple encodes per connection! right now server closes after one!
        # can add longer-lived connection (beyond this batch)
        #   BUT only if timing shows its worthwhile
        #   btw ok to let client complete an entire batch, that won't require server to handle multiple connections
        #     only need multi connection handling IF I allow longer-lived connections (like for entire life of LS/indexer)
        all_vecs = []
        total = len(texts)
        for i in range(0, total, batch_size):
            # FYI right now this is a new connection PER batch
            async with AsyncInferenceClient() as client:
                logger.info(f"    batch {i}-{i+batch_size} of {total}")
                batch = texts[i:i + batch_size]
                vecs = await client.encode({"texts": batch})
                all_vecs.append(vecs)

        return np.concatenate(all_vecs)

    vecs_np = await batched_encode(texts)
    return vecs_np

async def encode_passages(passages: list[str]) -> "np.ndarray":
    # FYI Qwen3 has NO passage/document label, only query side has Query:/Instruct:
    return await _encode_batch(passages)

def qwen3_format_query(text: str, instruct: Optional[str]) -> str:
    if instruct:
        return f'Instruct: {instruct}\nQuery:{text}'
    return f"Query: {text}"

async def encode_query(text: str, instruct: Optional[str]) -> "np.ndarray":
    return await _encode_batch([
        qwen3_format_query(text, instruct),
    ])

async def get_shape() -> int:
    # create a dummy vector to get dimensions (1024 for Qwen3-Embedding-0.6B)...
    # only used when first creating an index so NBD to leave it this way
    sample_text = "sample"
    sample_vec = await _encode_batch([
        sample_text,
    ])
    shape = sample_vec.shape[1]
    return shape
