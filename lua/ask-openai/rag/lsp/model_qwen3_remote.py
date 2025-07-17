from .logs import get_logger
from .qwen3 import known

logger = get_logger(__name__)

def ensure_model_loaded():

    with logger.timer("imports for qwen3 remote EmbedClient"):
        import numpy as np

    # FYI client opens a socket so still useful to defer until needed

def _encode(texts):
    import numpy as np
    from lsp.remote.comms import EmbedClient

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
            with EmbedClient() as client:
                logger.info(f"    batch {i}-{i+batch_size} of {total}")
                batch = texts[i:i + batch_size]
                vecs = client.encode({"texts": batch})
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

def get_detailed_instruct(task_description: str, query: str) -> str:
    # *** INSTRUCTION!
    return f'Instruct: {task_description}\nQuery:{query}'

def test_known_embeddings():
    input_texts = known.get_known_inputs()

    embeddings = _encode(input_texts)
    print(embeddings)

    query_embeddings = embeddings[:2]  # first two are queries
    passage_embeddings = embeddings[2:]  # last two are documents
    actual_scores = (query_embeddings @ passage_embeddings.T)
    print(f'{actual_scores=}')
    from numpy.testing import assert_array_almost_equal
    expected_scores = [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]]
    assert_array_almost_equal(actual_scores, expected_scores, decimal=3)
    print(f'{expected_scores=}')

if __name__ == "__main__":
    ensure_model_loaded()
    test_known_embeddings()
