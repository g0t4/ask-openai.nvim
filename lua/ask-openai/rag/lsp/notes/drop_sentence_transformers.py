#!/usr/bin/env python3 -m lsp.notes.drop_sentence_transformers

import logging
from lsp.logs import get_logger, logging_fwk_to_console

logger = get_logger("drop_ST")
logging_fwk_to_console(logging.DEBUG)

import torch.nn.functional as F
from rich import print

# from torch import Tensor # only needed for type hints... so not really needed

# unfortunately, at best this saves 100ms of 2300ms total on import timing...
#   this is most useful to understand how embeddings are calculated using last_hidden, etc.

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

model = BertModel.from_pretrained("intfloat/e5-base-v2")
tokenizer = BertTokenizer.from_pretrained("intfloat/e5-base-v2")

# Tokenize the input texts
batch_dict = tokenizer(input_texts, max_length=512, padding=True, truncation=True, return_tensors='pt')
logger.info(f'{batch_dict=}')

outputs = model(**batch_dict)
logger.info(f'{outputs=}')
logger.info(f'{outputs.last_hidden_state.shape=}')
logger.info(f'{outputs.last_hidden_state=}')
logger.info(f'{batch_dict["attention_mask"].shape=}')

embeddings = average_pool(outputs.last_hidden_state, batch_dict['attention_mask'])
logger.info(f'{embeddings=}')

# normalize embeddings
embeddings = F.normalize(embeddings, p=2, dim=1)
logger.info(f'{embeddings=}')

scores = (embeddings[:2] @ embeddings[2:].T) * 100
logger.info(f'{scores=}')
