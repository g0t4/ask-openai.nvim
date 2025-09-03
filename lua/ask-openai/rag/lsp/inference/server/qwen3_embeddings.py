import sys
import torch
import torch.nn.functional as F
import numpy as np

from torch import Tensor
from transformers import AutoTokenizer, AutoModel

from lsp.inference.qwen3.known import get_known_inputs, verify_qwen3_known_embeddings
from lsp.inference.server.helpers import auto_device
from lsp.logs import get_logger, logging_fwk_to_console

logger = get_logger(__name__)
enable_memory_logs = '--memory' in sys.argv

if __name__ == '__main__':
    logging_fwk_to_console("INFO")

# FYI! this is designed ONLY for cuda/5090s for socket server (remote embeddings)
#

def dump_device_memory_stats(message: str = ""):
    if not enable_memory_logs:
        return
    message = "" if message == "" else f" - {message}"  # add space

    # FYI https://docs.pytorch.org/docs/stable/torch_cuda_memory.html#torch-cuda-memory

    # TODO check which device is displayed for stats, should I explicitly choose or is current_device sufficient?

    torch.cuda.synchronize()
    allocated = torch.cuda.memory_allocated() / 1e9
    reserved = torch.cuda.memory_reserved() / 1e9
    max_allocated = torch.cuda.max_memory_allocated()
    max_reserved = torch.cuda.max_memory_reserved() / 1e9
    # cached = torch.cuda.memory_cached() / 1e9 # replaced by memory_reserved
    # stats = torch.cuda.memory_stats() # advanced stats
    # summary = torch.cuda.memory_summary() # nice table like nvidia-smi output
    # print(summary)
    # usage = torch.cuda.memory_usage() / 1e9 # usage stats in real time, how many GB read per last 1 second (or other unit of time)
    print(
        f"alloc={allocated:.2f} GB (max {max_allocated/1e9:.2f} GB), " \
        + f"reserv={reserved:.2f} GB (max {max_reserved:.2f} GB)" \
        + message \
    )

dump_device_memory_stats("before embedding model load")

# FYI - warnings... I believe both of these are false positives...
#   reproduce by running inference server on linux and connect with neovim LSP (change a doc and save it) ... during update it will show warning first time
#   FYI your initial known embeddings test cases might cause this to happen before you clear history and so in that case you might not see this warning.. not sure, just a heads up to maybe disable the clear scrollback if having trouble finding this
# TODO - You're using a Qwen2TokenizerFast tokenizer. Please note that with a fast tokenizer, using the `__call__` method is faster than using a method to encode the text followed by a call to the `pad` method to get a padded encoding.
# TODO - .venv/lib/python3.13/site-packages/transformers/tokenization_utils_base.py:2696: UserWarning: `max_length` is ignored when `padding`=`True` and there is no truncation strategy. To pad to max length, use `padding='max_length'`.

def last_token_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:
    left_padding = (attention_mask[:, -1].sum() == attention_mask.shape[0])
    if left_padding:
        result = last_hidden_states[:, -1]
        return result
    else:
        raise ValueError("Expected left padding, this code for right padding is carry over from prior example, make sure its correct if you switch to right padding")
        sequence_lengths = attention_mask.sum(dim=1) - 1
        batch_size = last_hidden_states.shape[0]
        return last_hidden_states[torch.arange(batch_size, device=last_hidden_states.device), sequence_lengths]
        # FYI ok to use device here b/c forward pass already placed onto device so keep on that one

# sizes: 0.6B (remember this is big for embeddings), also 4B and 8B
model_path = 'Qwen/Qwen3-Embedding-0.6B'
tokenizer = AutoTokenizer.from_pretrained(model_path, padding_side='left')
dump_device_memory_stats("after tokenizer loaded")

device = auto_device()
if device.type == 'cuda':
    # TODO would bfloat16 work better on 5090s?
    model_kwargs = dict(
        torch_dtype=torch.float16,
        attn_implementation="flash_attention_2",  # cuda only
        device_map="auto",  # DO NOT also call model.to(device) too!, must let accelerate handle placement
    )
else:
    raise ValueError("ONLY setup for CUDA device")

model = AutoModel.from_pretrained(model_path, **model_kwargs)

# disable cache altogether
# - cuts peak reserved memory by 50%, and 40% less allocated
# - caching should happen client side by not even requesting a re-embed of the exact same chunk
model.config.use_cache = False
# TODO! model.eval() too?

dump_device_memory_stats("after embedding model loaded")

logger.debug(f'{model.hf_device_map=}')
logger.info(f'[red bold] %s', model.device)

torch.cuda.reset_peak_memory_stats()

def encode(input_texts: list[str]) -> tuple[np.ndarray, list[list[np.int64]]]:

    with torch.inference_mode():
        batch_args = tokenizer(
            input_texts,
            padding=True,
            truncation=True,
            max_length=8192,
            return_tensors="pt",
        )

        # batch_args.to(model.device) # not needed with device_map='auto', right?
        outputs = model(**batch_args)
        embeddings = last_token_pool(outputs.last_hidden_state, batch_args['attention_mask'])
        norm: np.ndarray = F.normalize(embeddings, p=2, dim=1).cpu().numpy()

        # norm is ndarray (SEQ,EMBEDDING DIMENSION) => fix usage of matrix multi in verify_qwen3_known_embeddings so I can do norm.tolist() here too
        # batch_args is a Tensor
        return norm, batch_args['input_ids'].tolist()

def test_known_embeddings_in_process():
    from rich import print

    print("TESTING known embeddings from Qwen3 README...")
    input_texts = get_known_inputs()
    embeddings, _ = encode(input_texts)
    verify_qwen3_known_embeddings(embeddings, model_path)

if __name__ == "__main__":
    test_known_embeddings_in_process()
