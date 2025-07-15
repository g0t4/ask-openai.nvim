from lsp.logs import get_logger

logger = get_logger(__name__)

def get_detailed_instruct(task_description: str, query: str) -> str:
    # *** INSTRUCTION!
    return f'Instruct: {task_description}\nQuery:{query}'

def encode(input_texts):
    pass
    #
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
    pass

if __name__ == "__main__":
    main()
