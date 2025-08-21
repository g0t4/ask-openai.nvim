# Requires transformers>=4.51.0
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

from lsp.helpers import auto_device

# FYI links:
#   Qwen3 paper w.r.t. Embedding and Reranking: https://arxiv.org/pdf/2506.05176
#   hf repos:
#      0.6B: https://huggingface.co/Qwen/Qwen3-Reranker-0.6B
#      0.6B: https://huggingface.co/Qwen/Qwen3-Embedding-0.6B

model_path = "Qwen/Qwen3-Reranker-0.6B"
tokenizer = AutoTokenizer.from_pretrained(model_path, padding_side='left')
# TODO - You're using a Qwen2TokenizerFast tokenizer. Please note that with a fast tokenizer, using the `__call__` method is faster than using a method to encode the text followed by a call to the `pad` method to get a padded encoding.
# TODO - .venv/lib/python3.13/site-packages/transformers/tokenization_utils_base.py:2696: UserWarning: `max_length` is ignored when `padding`=`True` and there is no truncation strategy. To pad to max length, use `padding='max_length'`.

device = auto_device()
if device.type == 'cuda':
    model_kwargs = dict(
        torch_dtype=torch.float16,
        attn_implementation="flash_attention_2",  # cuda only
        device_map="auto",  # DO NOT also call model.to(device) too!, must let accelerate handle placement
    )
else:
    raise ValueError("ONLY setup for CUDA device")

# We recommend enabling flash_attention_2 for better acceleration and memory saving.
model = AutoModelForCausalLM.from_pretrained(model_path, **model_kwargs).eval()
# FYI reranker uses probabilities from yes/no tokens for relevance score
token_false_id = tokenizer.convert_tokens_to_ids("no")
token_true_id = tokenizer.convert_tokens_to_ids("yes")
#
chat_thread_prefix = "<|im_start|>system\nJudge whether the Document meets the requirements based on the Query and the Instruct provided. Note that the answer can only be \"yes\" or \"no\".<|im_end|>\n<|im_start|>user\n"
chat_thread_suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
chat_thread_prefix_tokens = tokenizer.encode(chat_thread_prefix, add_special_tokens=False)
chat_thread_suffix_tokens = tokenizer.encode(chat_thread_suffix, add_special_tokens=False)
max_length = 8192
max_user_tokens = max_length - len(chat_thread_prefix_tokens) - len(chat_thread_suffix_tokens)

instruct = 'Given a web search query, retrieve relevant passages that answer the query'

def format_rerank_instruction(_instruct, query, doc):
    if _instruct is None:
        _instruct = 'Given a user query and a document, determine if the document contains an answer to the query.'
    # NOTE layout is optimized for cache reuse! instruction/query are constant across a batch of documents
    return f"<Instruct>: {_instruct}\n<Query>: {query}\n<Document>: {doc}"

def move_to_gpu(tensors, device):
    for key in tensors:
        tensors[key] = tensors[key].to(device)
    return tensors

def tokenize_docs(_instruct: str, _query: str, _documents: list[str]):
    messages = [format_rerank_instruction(_instruct, _query, doc) for doc in _documents]
    messages_tokens = tokenizer(
        messages,
        padding=False,
        truncation='longest_first',
        return_attention_mask=False,
        max_length=max_user_tokens,
    )
    for i, message_tokens in enumerate(messages_tokens['input_ids']):
        # insert user message contents into the chat thread template (this way I don't have to tokenize the constant parts repeatedly
        messages_tokens['input_ids'][i] = chat_thread_prefix_tokens + message_tokens + chat_thread_suffix_tokens
    messages_tokens = tokenizer.pad(messages_tokens, padding=True, return_tensors="pt", max_length=max_length)
    return move_to_gpu(messages_tokens, model.device)

def compute_relevance(inputs, **kwargs):
    with torch.no_grad():
        batch_scores = model(**inputs).logits[:, -1, :]
        true_vector = batch_scores[:, token_true_id]
        false_vector = batch_scores[:, token_false_id]
        batch_scores = torch.stack([false_vector, true_vector], dim=1)
        # calculation to turn yes/no token logits into relevance score overall (per document)
        batch_scores = torch.nn.functional.log_softmax(batch_scores, dim=1)
        scores = batch_scores[:, 1].exp().tolist()
        return scores

def rerank(_instruct: str, _query: str, _documents: list[str]) -> list[float]:
    # for now assume instruct and query are constant for all documents, if I need mixed batching then I can address that later...
    # and actually I should encourage batching for same instruct/query else cache will be invalidated when instruct/query change
    tokenized_threads = tokenize_docs(_instruct, _query, _documents)
    return compute_relevance(tokenized_threads)

query1 = "What is the capital of China?"
query2 = "Explain gravity"

documents = [
    "The capital of China is Beijing.",
    "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
]

if __name__ == "__main__":
    from numpy.testing import assert_array_almost_equal

    # * query1
    actual_scores1 = rerank(instruct, query1, documents)
    print("scores1: ", actual_scores1)
    expected_scores1 = [0.99951171875, 5.066394805908203e-06]
    assert_array_almost_equal(actual_scores1, expected_scores1, decimal=3)

    # * query2
    actual_scores2 = rerank(instruct, query2, documents)
    print("scores2: ", actual_scores2)
    expected_scores2 = [4.947185516357422e-05, 0.99951171875]
    assert_array_almost_equal(actual_scores2, expected_scores2, decimal=3)
    print("All tests passed")
