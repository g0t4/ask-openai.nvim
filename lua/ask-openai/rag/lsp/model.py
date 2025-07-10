import os

from .logs import get_logger

logger = get_logger(__name__)

with logger.timer("importing sentence transformers"):
    from sentence_transformers import SentenceTransformer

# avoid checking for model files every time you load the model...
#   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
os.environ["TRANSFORMERS_OFFLINE"] = "1"

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

    def encode_passages(self, passages: list[str], show_progress_bar=False):
        texts = [f"passage: {p}" for p in passages]

        # FYI can split out later, this is only usage of multi-encode
        self.ensure_model_loaded()
        return self.model.encode(
            texts,
            normalize_embeddings=True,
            #
            # FYI CANNOT DO THIS IN LS! ok in standalone indexer (hence make it explicit as arg)
            show_progress_bar=show_progress_bar,
            #
            # device="cpu", # PRN do some testing of perf differences, left alone it is selecting mps (per logs)
        ).astype("float32")

    def encode_query(self, text: str):
        # "query: text" is the training query format
        # "passage: text" is the training document format
        return self._encode_text(f"query: {text}")

    def _encode_text(self, text: str):
        self.ensure_model_loaded()
        return self.model.encode(
            [text],
            normalize_embeddings=True,
            # device="cpu",
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
