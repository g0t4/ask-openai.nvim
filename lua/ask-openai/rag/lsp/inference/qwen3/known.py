from lsp.inference.client.embedder import qwen3_format_query

def get_known_inputs():

    # Each query must come with a one-sentence instruction that describes the task
    instruct = 'Given a web search query, retrieve relevant passages that answer the query'
    queries = [
        qwen3_format_query('What is the capital of China?', instruct),
        qwen3_format_query('Explain gravity', instruct),
    ]
    # No need to add instruction for retrieval documents
    documents = [
        "The capital of China is Beijing.",
        "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
    ]
    input_texts = queries + documents
    # prints for padding checks:
    for i, text in enumerate(input_texts):
        print(f'{i}: {len(text)=}')
    return input_texts

expected_scores_by_model_path = {
    # TODO ensure input_texts match! (for Qwen they appear to match
    # PRN might be useful to consolidate other config per model, i.e. embedding dimensions
    "Qwen/Qwen3-Embedding-0.6B": [[0.7646, 0.1414], [0.1355, 0.6000]],  # dimensions: 1024 (variable from 32+, IIUC)
    # "0.6B": [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]],
    "Qwen/Qwen3-Embedding-4B": [[0.7534, 0.1147], [0.0320, 0.6258]],  # dimension: 2560
    "Qwen/Qwen3-Embedding-8B": [[0.7493, 0.0751], [0.0880, 0.6318]],  # dimension: 4096
}

def verify_qwen3_known_embeddings(embeddings, model_path: str):
    query_embeddings = embeddings[:2]  # first two are queries
    passage_embeddings = embeddings[2:]  # last two are documents
    actual_scores = (query_embeddings @ passage_embeddings.T)
    from numpy.testing import assert_array_almost_equal
    expected_scores = expected_scores_by_model_path[model_path]
    print(f'{expected_scores=}')
    if expected_scores is None:
        raise Exception(f"Cannot find expected scores for ${model_path=}")
    assert_array_almost_equal(actual_scores, expected_scores, decimal=3)

    print(f'  {actual_scores=}')
    print(f'  {expected_scores=}')
    print(f"  [green bold]SCORES LOOK OK")
