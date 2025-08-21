# Requires transformers>=4.51.0
import torch
from transformers import AutoModel, AutoTokenizer, AutoModelForCausalLM

# FYI links:
#   Qwen3 paper w.r.t. Embedding and Reranking: https://arxiv.org/pdf/2506.05176
#   hf repos:
#      0.6B: https://huggingface.co/Qwen/Qwen3-Reranker-0.6B
#      0.6B: https://huggingface.co/Qwen/Qwen3-Embedding-0.6B

def format_rerank_instruction(instruction, query, doc):
    if instruction is None:
        instruction = 'Given a user query and a document, determine if the document contains an answer to the query.'
    # NOTE layout is optimized for cache reuse! instruction/query are constant across a batch of documents
    return f"<Instruct>: {instruction}\n<Query>: {query}\n<Document>: {doc}"

def move_to_gpu(tensors, device):
    for key in tensors:
        tensors[key] = tensors[key].to(device)
    return tensors

def tokenize(pairs):
    inputs = tokenizer(
        pairs,
        padding=False,
        truncation='longest_first',
        return_attention_mask=False,
        max_length=max_length - len(prefix_tokens) - len(suffix_tokens),
    )
    for i, ele in enumerate(inputs['input_ids']):
        inputs['input_ids'][i] = prefix_tokens + ele + suffix_tokens
    inputs = tokenizer.pad(inputs, padding=True, return_tensors="pt", max_length=max_length)
    return move_to_gpu(inputs, model.device)

@torch.no_grad()
def compute_logits(inputs, **kwargs):
    batch_scores = model(**inputs).logits[:, -1, :]
    true_vector = batch_scores[:, token_true_id]
    false_vector = batch_scores[:, token_false_id]
    batch_scores = torch.stack([false_vector, true_vector], dim=1)
    batch_scores = torch.nn.functional.log_softmax(batch_scores, dim=1)
    scores = batch_scores[:, 1].exp().tolist()
    return scores

tokenizer = AutoTokenizer.from_pretrained("Qwen/Qwen3-Reranker-0.6B", padding_side='left')
# model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen3-Reranker-0.6B").eval()
# We recommend enabling flash_attention_2 for better acceleration and memory saving.
model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen3-Reranker-0.6B", torch_dtype=torch.float16, attn_implementation="flash_attention_2").cuda().eval()
token_false_id = tokenizer.convert_tokens_to_ids("no")
token_true_id = tokenizer.convert_tokens_to_ids("yes")
max_length = 8192

prefix = "<|im_start|>system\nJudge whether the Document meets the requirements based on the Query and the Instruct provided. Note that the answer can only be \"yes\" or \"no\".<|im_end|>\n<|im_start|>user\n"
suffix = "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
prefix_tokens = tokenizer.encode(prefix, add_special_tokens=False)
suffix_tokens = tokenizer.encode(suffix, add_special_tokens=False)

task = 'Given a web search query, retrieve relevant passages that answer the query'

queries = [
    "What is the capital of China?",
    "Explain gravity",
]

documents = [
    "The capital of China is Beijing.",
    "Gravity is a force that attracts two bodies towards each other. It gives weight to physical objects and is responsible for the movement of planets around the sun.",
]

def rerank(_task: str, _query: str, documents: list[str]) -> list[float]:
    # for now assume task and query are constant for all documents, if I need mixed batching then I can address that later...
    # and actually I should encourage batching for same task/query else cache will be invalidated when task/query change
    prompts = [format_rerank_instruction(_task, _query, doc) for doc in documents]

    inputs = tokenize(prompts)
    scores = compute_logits(inputs)

print("scores: ", scores)
