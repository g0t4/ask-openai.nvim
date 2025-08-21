# Requires transformers>=4.51.0
import torch
from rich import print
from transformers import AutoModel, AutoTokenizer, AutoModelForCausalLM

def format_instruction(instruction, query, doc):
    if instruction is None:
        instruction = 'Given a web search query, retrieve relevant passages that answer the query'
    output = "<Instruct>: {instruction}\n<Query>: {query}\n<Document>: {doc}".format(instruction=instruction, query=query, doc=doc)
    return output

def process_inputs(pairs):
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
    for key in inputs:
        inputs[key] = inputs[key].to(model.device)
    return inputs

@torch.no_grad()
def compute_logits(inputs, **kwargs):
    batch_scores = model(**inputs).logits[:, -1, :]
    print(f"\nbatch_scores: {batch_scores}")
    print(f'  {type(batch_scores)=} {batch_scores.shape} {batch_scores.dtype}')
    true_vector = batch_scores[:, token_true_id]
    print(f"\ntrue_vector: {true_vector}")
    print(f'  {type(true_vector)=} {true_vector.shape} {true_vector.dtype}')
    false_vector = batch_scores[:, token_false_id]
    print(f"\nfalse_vector: {false_vector}")
    print(f'  {type(false_vector)=} {false_vector.shape} {false_vector.dtype}')
    batch_scores = torch.stack([false_vector, true_vector], dim=1)
    print(f"\nbatch_scores (stacked): {batch_scores}")
    print(f'  {type(batch_scores)=} {batch_scores.shape} {batch_scores.dtype}')
    batch_scores_softmax = torch.nn.functional.log_softmax(batch_scores, dim=1)
    print(f"\nbatch_scores_softmax: {batch_scores_softmax}")
    print(f'  {type(batch_scores_softmax)=} {batch_scores_softmax.shape} {batch_scores_softmax.dtype}')
    scores = batch_scores_softmax[:, 1].exp().tolist()
    print(f"\nscores: {scores}")
    print(f'  {type(scores)=} {type(scores[0])}')
    return scores

tokenizer = AutoTokenizer.from_pretrained("Qwen/Qwen3-Reranker-0.6B", padding_side='left')
model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen3-Reranker-0.6B").eval()
# We recommend enabling flash_attention_2 for better acceleration and memory saving.
# model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen3-Reranker-0.6B", torch_dtype=torch.float16, attn_implementation="flash_attention_2").cuda().eval()
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

# FYI score ~1 for both (cuz they match)
pairs = [format_instruction(task, query, doc) for query, doc in zip(queries, documents)]
# I added rev_pairs to see how score turns out with not matching query/doc, indeed score is ~0 for both!
rev_pairs = [format_instruction(task, query, doc) for query, doc in zip(reversed(queries), documents)]
pairs += rev_pairs
print("pairs", pairs)

# pairs = [format_instruction(
#     task,
#     "What are the odds of flipping a coin?",
#     "50% heads and 50% tails",
# )]
# pairs += [format_instruction(
#     task,
#     "What are the odds of flipping a coin?",
#     "1% heads and 99% tails",
# )]

# Tokenize the input texts
inputs = process_inputs(pairs)
scores = compute_logits(inputs)

print("scores: ", scores)
