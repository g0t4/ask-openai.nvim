def rerank_semantic_grep(query: str, documents: list[str]) -> list[float]:
    # TODO do I want this here or push out into the client?
    instruct = 'Does the document answer the user query?'
    return rerank(instruct, query, documents)
