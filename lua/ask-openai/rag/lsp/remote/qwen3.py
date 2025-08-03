import torch
import torch.nn.functional as F

from torch import Tensor
from transformers import AutoTokenizer, AutoModel

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
tokenizer = AutoTokenizer.from_pretrained(model_path, padding_side='left')


device = auto_device()
if device.type == 'cuda':
    # TODO would bfloat16 work better on 5090s?
    model_kwargs = dict(
        torch_dtype=torch.float16,
        attn_implementation="flash_attention_2",  # cuda only
        device_map="auto",  # DO NOT also call model.to(device) too!, must let accelerate handle placement
    )
    # TODO test timing of shared vs not sharded (w/ device_map="auto") on dual 5090s... I doubt it helps materially, if not maybe just go with model.to("cuda") to use one only?
else:
    raise ValueError("ONLY setup for CUDA device")

model = AutoModel.from_pretrained(model_path, **model_kwargs)

logger.debug(f'{model.hf_device_map=}')
logger.info(f'[red bold] %s', model.device)

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
        return norm, batch_args['input_ids']

def test_known_embeddings():
    from rich import print

    print("TESTING known embeddings from Qwen3 README...")
    input_texts = get_known_inputs()
    embeddings, _ = encode(input_texts)
    verify_known_embeddings(embeddings)

if __name__ == "__main__":
    test_known_embeddings()
