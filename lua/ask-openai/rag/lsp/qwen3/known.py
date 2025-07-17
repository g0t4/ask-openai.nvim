def get_known_inputs():

    def get_detailed_instruct(task_description: str, query: str) -> str:
        return f'Instruct: {task_description}\nQuery:{query}'

    # Each query must come with a one-sentence instruction that describes the task
    task = 'Given a web search query, retrieve relevant passages that answer the query'
    queries = [
        get_detailed_instruct(task, 'What is the capital of China?'),
        get_detailed_instruct(task, 'Explain gravity'),
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

def validate_embeddings(embeddings):

    query_embeddings = embeddings[:2]  # first two are queries
    passage_embeddings = embeddings[2:]  # last two are documents
    actual_scores = (query_embeddings @ passage_embeddings.T)
    from numpy.testing import assert_array_almost_equal
    expected_scores = [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]]
    assert_array_almost_equal(actual_scores, expected_scores, decimal=3)

    print(f'  {actual_scores=}')
    print(f'  {expected_scores=}')
    print(f"  [green bold]SCORES LOOK OK")
