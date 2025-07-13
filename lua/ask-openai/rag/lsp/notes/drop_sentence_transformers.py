#!/usr/bin/env python3 -m lsp.notes.drop_sentence_transformers

import logging
import os

import torch
from lsp.logs import get_logger, logging_fwk_to_console, LogTimer

logger = get_logger("drop_ST")
logging_fwk_to_console(logging.DEBUG)

with LogTimer("import torch.nn.functional as F", logger):
    import torch.nn.functional as F

# from torch import Tensor # only needed for type hints... so not really needed

# unfortunately, at best this saves 100ms of 2300ms total on import timing...
#   this is most useful to understand how embeddings are calculated using last_hidden, etc.

with LogTimer("import BertModel/Tokenizer", logger):
    # must come before import so it doesn't check model load on HF later
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    from transformers import BertModel, BertTokenizer

def average_pool(last_hidden_states: "Tensor", attention_mask: "Tensor") -> "Tensor":
    last_hidden = last_hidden_states.masked_fill(~attention_mask[..., None].bool(), 0.0)
    return last_hidden.sum(dim=1) / attention_mask.sum(dim=1)[..., None]

# Each input text should start with "query: " or "passage: ".
# For tasks other than retrieval, you can simply use the "query: " prefix.
input_texts = [
    'query: how much protein should a female eat',
    'query: summit define',
    "passage: As a general guideline, the CDC's average requirement of protein for women ages 19 to 70 is 46 grams per day. But, as you can see from this chart, you'll need to increase that if you're expecting or training for a marathon. Check out the chart below to see how much protein you should be eating each day.",
    "passage: Definition of summit for English Language Learners. : 1  the highest point of a mountain : the top of a mountain. : 2  the highest level. : 3  a meeting or series of meetings between the leaders of two or more governments.",
]

device = torch.device(
    'cuda' if torch.cuda.is_available() else \
    'mps' if torch.backends.mps.is_available() else \
    'cpu'
)

with LogTimer("load model/tokenizer", logger):
    model = BertModel.from_pretrained("intfloat/e5-base-v2").to(use_device)
    tokenizer = BertTokenizer.from_pretrained("intfloat/e5-base-v2")

logger.info(f"loaded on device: {model.device=}")

with LogTimer("encode-direct", logger):

    inputs = tokenizer(
        input_texts,
        padding=True,
        truncation=True,
        return_tensors='pt',
    ).to(use_device)

    with torch.no_grad():
        outputs = model(**inputs)
        token_embeddings = outputs.last_hidden_state  # (batch, seq_len, hidden)

        attention_mask = inputs['attention_mask'].unsqueeze(-1)  # (batch, seq_len, 1)
        masked_embeddings = token_embeddings * attention_mask

        summed = masked_embeddings.sum(dim=1)
        counts = attention_mask.sum(dim=1)
        embeddings = summed / counts  # average pooling

        embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)

#
#     batch_dict_pre = tokenizer(
#         input_texts,
#         max_length=512,
#         padding=True,
#         truncation=True,
#         return_tensors='pt',
#     )
#     batch_dict = {k: v.to(model.device) for k, v in batch_dict_pre.items()}
#
#     outputs = model(**batch_dict)
#
#     embeddings = average_pool(outputs.last_hidden_state, batch_dict['attention_mask'])
#
#     # normalize embeddings
#     embeddings = F.normalize(embeddings, p=2, dim=1)
#
#
    scores = (embeddings[:2] @ embeddings[2:].T) * 100

# logger.info(f'{batch_dict=}')
# logger.info(f'{outputs=}')
# logger.info(f'{outputs.last_hidden_state.shape=}')
# logger.info(f'{outputs.last_hidden_state=}')
# logger.info(f'{batch_dict["attention_mask"].shape=}')
# logger.info(f'{embeddings_before_norm=}')
# for k, v in batch_dict.items():
#     logger.info(f'{k} {v.device=} {v.dtype=} {v.shape=}')
#
logger.info(f'{embeddings=} {embeddings.device=} {embeddings.dtype=} {embeddings.shape=}')

logger.info(f'{scores=} {scores.device=} {scores.dtype=} {scores.shape=}')
