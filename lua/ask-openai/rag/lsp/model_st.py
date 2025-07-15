import torch
import os

from .logs import get_logger

logger = get_logger(__name__)

class ModelWrapper:

    # FYI there is a test case to validate encoding:
    #   python3 indexer_tests.py  TestBuildIndex.test_encode_and_search_index

    @property
    def model(self):
        if hasattr(self, "_model"):
            return self._model

        with logger.timer("import numpy"):
            # FYI pre-load so timing is never skewed on encode
            import numpy as np

        with logger.timer("importing sentence transformers"):

            # do not check hugging face for newer version, use offline cache only
            #   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
            # FYI must be set BEFORE importing SentenceTransformer, setting after (even if before model load) doesn't work
            os.environ["TRANSFORMERS_OFFLINE"] = "1"

            from sentence_transformers import SentenceTransformer  # 2+ seconds to import (mostly torch/transformer deps that even if I use BertModel directly, I cannot avoid the import timing)

        # TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model
        # model_name = "intfloat/e5-base-v2"
        model_name = "Qwen/Qwen3-Embedding-0.6B"
        with logger.timer(f"Load model {model_name}"):
            self._model = SentenceTransformer(model_name)

        return self._model

    def ensure_model_loaded(self):
        self.model  # access model to trigger load

    @torch.no_grad()
    def _encode(self, texts):
        import numpy as np

        vecs_np = self.model.encode(
            texts,
            normalize_embeddings=True,
            # device="cpu",
        ).astype("float32")

        return vecs_np

    def encode_passages(self, passages: list[str]):
        texts = [f"passage: {p}" for p in passages]
        # TODO test refactored _encode() shared method:
        return self._encode(texts)

    def encode_query(self, text: str):
        # "query: text" is the training query format
        # "passage: text" is the training document format
        return self._encode_text(f"query: {text}")

    def _encode_text(self, text: str):
        # FYI model.encode will encode a list of texts, so just encode a single text
        # TODO test refactored _encode() shared method:
        return self._encode([text])

    def get_shape(self) -> None:
        # Create a dummy vector to get dimensions
        # TODO! is this the best way to get this?
        #  should I just hardcode for now? (per model?)
        sample_text = "passage: sample"
        sample_vec = self._encode_text(sample_text)
        shape = sample_vec.shape[1]
        return shape

model_wrapper = ModelWrapper()
