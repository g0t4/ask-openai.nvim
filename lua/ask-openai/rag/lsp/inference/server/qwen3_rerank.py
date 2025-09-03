import torch
import numpy as np
from transformers import AutoTokenizer, AutoModelForCausalLM
from lsp.inference.server.helpers import auto_device

# FYI links:
#   Qwen3 paper w.r.t. Embedding and Reranking: https://arxiv.org/pdf/2506.05176
#   hf repos:
#      0.6B: https://huggingface.co/Qwen/Qwen3-Reranker-0.6B
#      0.6B: https://huggingface.co/Qwen/Qwen3-Embedding-0.6B

model_path = "Qwen/Qwen3-Reranker-0.6B"
tokenizer = AutoTokenizer.from_pretrained(model_path, padding_side='left')

device = auto_device()
if device.type == 'cuda':
    model_kwargs = dict(
        torch_dtype=torch.float16,
        attn_implementation="flash_attention_2",  # cuda only
        device_map="auto",  # DO NOT also call model.to(device) too!, must let accelerate handle placement
    )
else:
    raise ValueError("ONLY setup for CUDA device")

model = AutoModelForCausalLM.from_pretrained(model_path, **model_kwargs).eval()
# TODO! do some testing of re-ranker memory usage
#  would it benefit from caching at all?
#    i.e. when I re-rank the same query across multiple docs, is there a material boost from caching the query?
#      IIRC query comes first in "prompt" so it would be cacheable
#      FIM queries are long enough to matter for this
#    PERHAPS decide request by request if you want to cache?
#    - i.e. my RAG telescope picker the query is tiny so not much of a point there
#    - FIM query is up to 1500 chars
#    - MAYBE use len(query) to decide on caching?
#  not sure it would but I suppose my search tool might benefit from it?
#  but, before optimizing this here, let's test it first
#  using realistic loads
# model.config.use_cache = False
# TODO! model.eval() too?

#
# FYI reranker uses probabilities from yes/no tokens for relevance score
TOKEN_ID_NO = tokenizer.convert_tokens_to_ids("no")
TOKEN_ID_YES = tokenizer.convert_tokens_to_ids("yes")
#
thread_prefix = "<|im_start|>system\nJudge whether the Document meets the requirements based on the Query and the Instruct provided. Note that the answer can only be \"yes\" or \"no\".<|im_end|>\n<|im_start|>user\n"
thread_suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
thread_prefix_tokens = tokenizer.encode(thread_prefix, add_special_tokens=False)
thread_suffix_tokens = tokenizer.encode(thread_suffix, add_special_tokens=False)
max_length = 8192
max_user_tokens = max_length - len(thread_prefix_tokens) - len(thread_suffix_tokens)

def move_to_gpu(tensors, device):
    for key in tensors:
        tensors[key] = tensors[key].to(device)
    return tensors

def tokenize_docs(instruct: str, query: str, documents: list[str]):
    if instruct is None or instruct.strip() == "":
        raise ValueError("instruct must be provided")

    # tokenize common prefix once:
    instruct_query = f"<Instruct>: {instruct}\n<Query>: {query}\n<Document>: "
    instruct_query_tokens = tokenizer.encode(instruct_query, add_special_tokens=False)

    # NOTE layout is optimized for cache reuse! instruction/query are constant across a batch of documents
    documents_tokens = tokenizer(
        documents,
        padding=False,
        truncation='longest_first',
        return_attention_mask=False,
        max_length=max_user_tokens,
    )
    for i, doc_tokens in enumerate(documents_tokens['input_ids']):
        # insert user message contents into the chat thread template (this way I don't have to tokenize the constant parts repeatedly
        documents_tokens['input_ids'][i] = thread_prefix_tokens + instruct_query_tokens + doc_tokens + thread_suffix_tokens
    documents_tokens = tokenizer.pad(documents_tokens, padding=True, return_tensors="pt", max_length=max_length)
    return move_to_gpu(documents_tokens, model.device)

def compute_relevance_scores(tokenized_inputs):
    with torch.inference_mode():
        output_logits = model(**tokenized_inputs).logits[:, -1, :]
        yes_logits = output_logits[:, TOKEN_ID_YES]
        no_logits = output_logits[:, TOKEN_ID_NO]
        logits_no_and_yes = torch.stack([no_logits, yes_logits], dim=1)
        # calculation to turn yes/no token logits into relevance score overall (per document)
        log_softmax = torch.nn.functional.log_softmax(logits_no_and_yes, dim=1)
        relevance_scores = log_softmax[:, 1].exp().tolist()
        return relevance_scores

def rerank(instruct: str, query: str, documents: list[str]) -> tuple[list[float], list[list[np.int64]]]:

    # for now assume instruct and query are constant for all documents, if I need mixed batching then I can address that later...
    # and actually I should encourage batching for same instruct/query else cache will be invalidated when instruct/query change

    # TODO check for cancelation
    tokenized_threads = tokenize_docs(instruct, query, documents)
    # TODO check for cancellation before rerank
    return compute_relevance_scores(tokenized_threads), tokenized_threads.input_ids.tolist()

def main():
    from numpy.testing import assert_array_almost_equal

    # * test data
    query1 = "What is the capital of China?"
    query2 = "Explain gravity"
    documents = [
        "The capital of China is Beijing.",
        "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
    ]
    instruct = 'Given a web search query, retrieve relevant passages that answer the query'

    # * query1
    actual_scores1, _ = rerank(instruct, query1, documents)
    print("scores1: ", actual_scores1)
    expected_scores1 = [0.99951171875, 5.066394805908203e-06]
    assert_array_almost_equal(actual_scores1, expected_scores1, decimal=3)

    # * query2
    actual_scores2, _ = rerank(instruct, query2, documents)
    print("scores2: ", actual_scores2)
    expected_scores2 = [4.947185516357422e-05, 0.99951171875]
    assert_array_almost_equal(actual_scores2, expected_scores2, decimal=3)
    print("All tests passed")

if __name__ == "__main__":
    main()
