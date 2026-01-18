from lsp.logs import get_logger, logging_fwk_to_console

logger = get_logger(__name__)

import httpx

def encode(input_texts: list[str]):
    payload = {'input': input_texts}
    response = httpx.post('http://ollama:8013/embedding', json=payload)
    embeddings = response.json()

    return embeddings

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
    logging_fwk_to_console("INFO")
    with logger.timer("/embeddings RT"):
        embeddings = encode([
            # one document is 90ms R/T that is awesome
            "This is a test.",
            # "This is another test.",
            # "This is a third test.",
        ])
    # print(embeddings)

if __name__ == "__main__":
    main()
