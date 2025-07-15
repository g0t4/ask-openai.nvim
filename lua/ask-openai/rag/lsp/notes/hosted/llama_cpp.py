from lsp.logs import get_logger

logger = get_logger(__name__)

def get_detailed_instruct(task_description: str, query: str) -> str:
    # *** INSTRUCTION!
    return f'Instruct: {task_description}\nQuery:{query}'

import httpx

def encode(input_texts: list[str]):
    payload = {'input': input_texts}
    response = httpx.post('http://ollama:8013/embedding', json=payload)
    embeddings = response.json()
    normalized_embeddings = []
    for vec in embeddings:
        norm = sum(x**2 for x in vec)**0.5
        normalized = [x / norm for x in vec]
        normalized_embeddings.append(normalized)
    return normalized_embeddings

    # with torch.no_grad():
    #     batch_args = tokenizer(
    #         input_texts,
    #         padding=True,
    #         truncation=True,
    #         max_length=8192,
    #         return_tensors="pt",
    #     )
    #     batch_args.to(model.device)
    #     outputs = model(**batch_args)
    #     embeddings = last_token_pool(outputs.last_hidden_state, batch_args['attention_mask'])
    #     return F.normalize(embeddings, p=2, dim=1)

def main():
    encode(["This is a test.", "This is another test.", "This is a third test."])

if __name__ == "__main__":
    main()
