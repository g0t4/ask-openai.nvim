import torch
import torch.nn.functional as F

from torch import Tensor
# from transformers import AutoTokenizer, AutoModel
from llama_cpp import Llama, np

from lsp.qwen3.known import get_known_inputs, verify_known_embeddings

from ..helpers import auto_device
from ..logs import get_logger, logging_fwk_to_console

logger = get_logger(__name__)
if __name__ == '__main__':
    logging_fwk_to_console("INFO")
#
# FYI! this is designed ONLY for cuda/5090s for socket server (remote embeddings)
#

def last_token_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:

    left_padding = (attention_mask[:, -1].sum() == attention_mask.shape[0])
    if left_padding:
        result = last_hidden_states[:, -1]
        return result
    else:
        sequence_lengths = attention_mask.sum(dim=1) - 1
        batch_size = last_hidden_states.shape[0]
        return last_hidden_states[torch.arange(batch_size, device=last_hidden_states.device), sequence_lengths]

# sizes: 0.6B (remember this is big for embeddings), also 4B and 8B
model_path = 'Qwen/Qwen3-Embedding-0.6B'
# tokenizer = AutoTokenizer.from_pretrained(model_path, padding_side='left')
# 'Qwen/Qwen3-Embedding-0.6B-GGUF'  # use w/ llama-cpp-python? instead of transformers?
#  NOTE right now you are doing fine w/ 0.6B full precision ... stick with it for now

# device = auto_device()
# if device.type == 'cuda':
#     # TODO would bfloat16 work better on 5090s?
#     model_kwargs = dict(
#         torch_dtype=torch.float16,
#         attn_implementation="flash_attention_2",  # cuda only
#         device_map="auto",  # DO NOT also call model.to(device) too!, must let accelerate handle placement
#     )
#     # TODO test timing of shared vs not sharded (w/ device_map="auto") on dual 5090s... I doubt it helps materially, if not maybe just go with model.to("cuda") to use one only?
# else:
#     raise ValueError("ONLY setup for CUDA device")

# model = AutoModel.from_pretrained(model_path, **model_kwargs)
llm = Llama.from_pretrained(
    repo_id="Qwen/Qwen3-Embedding-0.6B-GGUF",
    # TODO later test q8 if fp16 has passing tests
    # only q8 and f16
    filename="*f16.gguf",  # try fp16 first to minimize chance of precision losses in tests
    embedding=True,
    n_ctx=8192,
    # n_threads=16,
    n_gpu_layers=-1,  # put all layers on GPU if built with cuBLAS
    verbose=False,
)

# FYI use cosine similarity to gauge accuracy of quantized models
# from sklearn.metrics.pairwise import cosine_similarity
# cosine_similarity([embedding_orig], [embedding_quant])

# logger.debug(f'{model.hf_device_map=}')
# logger.info(f'[red bold] %s', model.device)

def encode(input_texts):

    # * one at a time, not batched... WORKING
    # vectors = []
    # for i, text in enumerate(input_texts):
    #     result = np.array(llm.embed(text))
    #     if result.ndim == 2:
    #         # Mimic last_token_pool
    #         vec = result[-1]  # assumes right-padding
    #     else:
    #         vec = result
    #     vec = vec / np.linalg.norm(vec)  # normalize
    #     print(f"text[{i}]: shape={vec.shape}, norm={np.linalg.norm(vec):.4f}")
    #     vectors.append(vec)
    # return np.stack(vectors), None

    # * batched: WORKING ***! BUT under the hood it is NOT batched, it is one at a time AFAICT:
    # https://github.com/abetlen/llama-cpp-python/blob/main/llama_cpp/llama.py#L1077C4-L1081C42
    vectors = [np.array(llm.embed(text)) for text in input_texts]
    final = []
    for v in vectors:
        result = v
        if result.ndim == 2:
            # Mimic last_token_pool
            vec = result[-1]  # assumes right-padding # * umm this s/b left-padding?
        else:
            vec = result
        vec = vec / np.linalg.norm(vec)  # normalize
        print(f"shape={vec.shape}, norm={np.linalg.norm(vec):.4f}")
        final.append(vec)
    return np.stack(final), None

    # with torch.no_grad():
    #     batch_args = tokenizer(
    #         input_texts,
    #         padding=True,
    #         truncation=True,
    #         max_length=8192,
    #         return_tensors="pt",
    #     )
    #
    #     batch_args.to(model.device)
    #     outputs = model(**batch_args)
    #     embeddings = last_token_pool(outputs.last_hidden_state, batch_args['attention_mask'])
    #     norm = F.normalize(embeddings, p=2, dim=1).cpu().numpy()
    #     return norm, batch_args['input_ids']

def test_known_embeddings():
    from rich import print

    print("TESTING known embeddings from Qwen3 README...")
    input_texts = get_known_inputs()
    embeddings, _ = encode(input_texts)
    verify_known_embeddings(embeddings)
    llm.__del__() # else unhandled exception during shutdown

if __name__ == "__main__":
    test_known_embeddings()
