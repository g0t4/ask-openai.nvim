#
# FYI! this is designed ONLY for cuda/5090s for socket server (remote embeddings)
#

import torch
import torch.nn.functional as F

from torch import Tensor
from transformers import AutoTokenizer, AutoModel

from lsp.logs import get_logger

logger = get_logger(__name__)

def last_token_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:

    left_padding = (attention_mask[:, -1].sum() == attention_mask.shape[0])
    if left_padding:
        result = last_hidden_states[:, -1]
        return result
    else:
        sequence_lengths = attention_mask.sum(dim=1) - 1
        batch_size = last_hidden_states.shape[0]
        return last_hidden_states[torch.arange(batch_size, device=last_hidden_states.device), sequence_lengths]

def get_detailed_instruct(task_description: str, query: str) -> str:
    # *** INSTRUCTION!
    return f'Instruct: {task_description}\nQuery:{query}'

device = torch.device(
    'cuda' if torch.cuda.is_available() else \
    'mps' if torch.backends.mps.is_available() else \
    'cpu'
)
# FYI padding_style is w.r.t. the longest sequence in the batch, the rest are padded (right by default) or to the left if specified here:
# FFS on MPS: left padding fails, but right padding works...
#     on CUDA: both left and right padding work?!
#     as in include/remove the padding_side="left"
tokenizer = AutoTokenizer.from_pretrained('Qwen/Qwen3-Embedding-0.6B', padding_side='left')

if device.type == 'mps':
    model_kwargs = dict(torch_dtype=torch.float16, )
elif device.type == 'cuda':
    # TODO would bfloat16 work better on 5090s?
    model_kwargs = dict(
        torch_dtype=torch.float16,
        attn_implementation="flash_attention_2",  # cuda only
        device_map="auto",
    )
else:
    raise ValueError("DEVICE should be CUDA/MPS... but is {device.type}")

model = AutoModel.from_pretrained('Qwen/Qwen3-Embedding-0.6B', **model_kwargs).to(device)

logger.info(f"{model.device=}")

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
        norm = F.normalize(embeddings, p=2, dim=1).cpu().numpy()
        return norm

def test_known_embeddings():
    # ! test the model config above produces correct embeddings for pre-canned examples
    # ! taken from the Qwen3 README (had published values)
    # TODO! can I find more published examples for a test suite to validate my config is correct?
    # TODO! on startup run some of these tests?

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

    embeddings = encode(input_texts)

    query_embeddings = embeddings[:2]  # first two are queries
    passage_embeddings = embeddings[2:]  # last two are documents
    actual_scores = (query_embeddings @ passage_embeddings.T)
    from numpy.testing import assert_array_almost_equal
    expected_scores = [[0.7645568251609802, 0.14142508804798126], [0.13549736142158508, 0.5999549627304077]]
    assert_array_almost_equal(actual_scores, expected_scores, decimal=3)
    print(f'{actual_scores=}')
    print(f'{expected_scores=}')

if __name__ == "__main__":
    test_known_embeddings()
