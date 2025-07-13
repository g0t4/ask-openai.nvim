#!/usr/bin/env python3 -m lsp.notes.drop_sentence_transformers

import logging
import os

from lsp.logs import get_logger, logging_fwk_to_console

logger = get_logger("drop_ST")
logging_fwk_to_console(logging.DEBUG)

with logger.timer("import torch.nn.functional as F"):
    import torch.nn.functional as F
    import torch

# from torch import Tensor # only needed for type hints... so not really needed

with logger.timer("import BertModel/Tokenizer"):
    # must come before import so it doesn't check model load on HF later
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    from transformers import BertModel, BertTokenizer

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

with logger.timer("load model/tokenizer"):
    # !!! model load is < 100ms, huge improvement over the 500ms for SentenceTransformer
    model = BertModel.from_pretrained("intfloat/e5-base-v2").to(device)
    tokenizer = BertTokenizer.from_pretrained("intfloat/e5-base-v2")

logger.info(f"loaded on device: {model.device=}")

with logger.timer("encode-direct"):

    inputs = tokenizer(
        input_texts,
        padding=True,
        truncation=True,
        return_tensors='pt',
    ).to(model.device)

    with torch.no_grad():
        outputs = model(**inputs)
        token_embeddings = outputs.last_hidden_state  # (batch, seq_len, hidden)

        attention_mask = inputs['attention_mask'].unsqueeze(-1)  # (batch, seq_len, 1)
        masked_embeddings = token_embeddings * attention_mask

        summed = masked_embeddings.sum(dim=1)
        counts = attention_mask.sum(dim=1)
        embeddings = summed / counts  # average pooling

        embeddings = F.normalize(embeddings, p=2, dim=1)

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
