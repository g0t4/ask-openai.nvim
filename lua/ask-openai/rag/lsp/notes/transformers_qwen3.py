# testing this b/c on my mac, memory explodes when using sentence transformers to access qwen3 model for encoding
#
# Requires transformers>=4.51.0

import torch
import torch.nn.functional as F

from torch import Tensor
from transformers import AutoTokenizer, AutoModel

def last_token_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:
    left_padding = (attention_mask[:, -1].sum() == attention_mask.shape[0])
    if left_padding:
        return last_hidden_states[:, -1]
    else:
        sequence_lengths = attention_mask.sum(dim=1) - 1
        batch_size = last_hidden_states.shape[0]
        return last_hidden_states[torch.arange(batch_size, device=last_hidden_states.device), sequence_lengths]

def get_detailed_instruct(task_description: str, query: str) -> str:
    # *** INSTRUCTION!
    return f'Instruct: {task_description}\nQuery:{query}'

# Each query must come with a one-sentence instruction that describes the task
task = 'Given a web search query, retrieve relevant passages that answer the query'

tokenizer = AutoTokenizer.from_pretrained('Qwen/Qwen3-Embedding-0.6B', padding_side='left')
model = AutoModel.from_pretrained('Qwen/Qwen3-Embedding-0.6B')

# We recommend enabling flash_attention_2 for better acceleration and memory saving.
# model = AutoModel.from_pretrained('Qwen/Qwen3-Embedding-0.6B', attn_implementation="flash_attention_2", torch_dtype=torch.float16).cuda()

def encode(input_texts):

    with torch.no_grad():
        batch_args = tokenizer(
            input_texts,
            padding=True,
            truncation=True,
            max_length=8192,
            return_tensors="pt",
        )
        batch_args.to(model.device)
        outputs = model(**batch_args)
        embeddings = last_token_pool(outputs.last_hidden_state, batch_args['attention_mask'])
        return F.normalize(embeddings, p=2, dim=1)

def main():
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

    all_ever_scores = []
    for _ in range(1, 100):
        embeddings = encode(input_texts)
        query_embeddings = embeddings[:2]  # first two are queries
        passage_embeddings = embeddings[2:]  # last two are documents
        scores = (query_embeddings @ passage_embeddings.T)
        print(f'{scores=}')
        all_ever_scores.append(scores)
        from numpy.testing import assert_array_almost_equal
        expected_scores = [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]]
        assert_array_almost_equal(scores.detach().numpy(), expected_scores, decimal=6)

if __name__ == "__main__":
    main()
