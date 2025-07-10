from dataclasses import dataclass
from .logs import get_logger

logger = get_logger(__name__)

with logger.timer("importing sentence transformers"):
    from sentence_transformers import SentenceTransformer

class ModelWrapper:
    model: SentenceTransformer

    # FYI there is a test case to validate encoding:
    #   python3 indexer.tests.py  TestBuildIndex.test_encode_and_search_index

    def ensure_model_loaded(self):
        if hasattr(self, "model"):
            return

        # TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model
        model_name = "intfloat/e5-base-v2"
        with logger.timer(f"Load model {model_name}"):
            self.model = SentenceTransformer(model_name)

    def encode_passage(self, text: str):
        return self._encode_text(f"passage: {text}")

    def encode_query(self, text: str):
        # "query: text" is the training query format
        # "passage: text" is the training document format
        return self._encode_text(f"query: {text}")

    def _encode_text(self, text: str):
        self.ensure_model_loaded()
        return self.model.encode(
            [text],
            normalize_embeddings=True,
            # device="cpu", # TODO should I set this or no?
        ).astype("float32")

    def get_shape(self) -> None:
        # Create a dummy vector to get dimensions
        # TODO! is this the best way to get this?
        #  should I just hardcode for now? (per model?)
        sample_text = "passage: sample"
        sample_vec = self._encode_text(sample_text)
        shape = sample_vec.shape[1]
        return shape

model_wrapper = ModelWrapper()
