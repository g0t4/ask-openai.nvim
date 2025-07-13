#!/usr/bin/env python3 -m lsp.notes.with_st

import logging
import os
from lsp.logs import get_logger, logging_fwk_to_console, LogTimer

logger = get_logger("drop_ST")
logging_fwk_to_console(logging.DEBUG)

with LogTimer("import torch.nn.functional as F", logger):
    import torch.nn.functional as F

# from torch import Tensor # only needed for type hints... so not really needed

# unfortunately, at best this saves 100ms of 2300ms total on import timing...
#   this is most useful to understand how embeddings are calculated using last_hidden, etc.

with logger.timer("importing sentence transformers"):

    # do not check hugging face for newer version, use offline cache only
    #   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
    # FYI must be set BEFORE importing SentenceTransformer, setting after (even if before model load) doesn't work
    os.environ["TRANSFORMERS_OFFLINE"] = "1"

    from sentence_transformers import SentenceTransformer  # 2+ seconds to import (mostly torch/transformer deps that even if I use BertModel directly, I cannot avoid the import timing)

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

with LogTimer("load model/tokenizer", logger):
    model_name = "intfloat/e5-base-v2"
    model = SentenceTransformer(model_name)

logger.info(f"loaded on device: {next(model.parameters()).device}")

with LogTimer("encode", logger):
    embeddings = model.encode(
        input_texts,
        normalize_embeddings=True,
        # device="cpu", # TODO! verify timing differences (if any) are not due to device selection
    ).astype("float32")

    scores = (embeddings[:2] @ embeddings[2:].T) * 100

logger.info(f'{embeddings=}')
logger.info(f'{scores=}')
