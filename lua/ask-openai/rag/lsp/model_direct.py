import os

# ! TERRIBLE encode performance (30 sec for this ask-openai repo) vs 22s with model_st ...
# YOU NEED PERF tests and a real reason to even try this again... stop wasting your time
#  part of this issue is no doubt all the damn data conversions and making sure the right device is used...
#  know what you are optimizing first and honestly 100ms for re-encode is not justifiably terrible, esp if I end up WORSE with _direct!


from .logs import get_logger

logger = get_logger(__name__)

class ModelWrapper:

    @property
    def model(self):
        if hasattr(self, "_model"):
            return self._model

        with logger.timer("import torch/numpy"):
            # FYI leave F import here so its front loaded for timing comparisons even though I only need it at encode time
            import torch.nn.functional as F
            import torch
            import numpy as np

        with logger.timer("import BertModel/Tokenizer"):
            # must come before import so it doesn't check model load on HF later
            os.environ["TRANSFORMERS_OFFLINE"] = "1"
            from transformers import BertModel, BertTokenizer

        device = torch.device(
            'cuda' if torch.cuda.is_available() else \
            'mps' if torch.backends.mps.is_available() else \
            'cpu'
        )

        with logger.timer("load model/tokenizer"):
            # ! model load is < 100ms, huge improvement over the 500ms for SentenceTransformer
            model_name = "intfloat/e5-base-v2"
            self._model = BertModel.from_pretrained(model_name).to(device)
            self._tokenizer = BertTokenizer.from_pretrained(model_name)
            #
            # TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model

        logger.info(f"loaded on device: {self._model.device=}")

        return self._model

    @property
    def tokenizer(self):
        self.model  # ensure model and tokenizer are loaded
        return self._tokenizer

    def encode(self, texts):
        # re-imports just so they don't run when module loads, these also are already imported on model load so should be 0 time here
        import torch.nn.functional as F
        import torch
        import numpy as np

        with logger.timer("encode-direct"):

            inputs = self.tokenizer(
                texts,
                padding=True,
                truncation=True,
                return_tensors='pt',
            ).to(self.model.device)

            with torch.no_grad():
                outputs = self.model(**inputs)
                token_embeddings = outputs.last_hidden_state  # (batch, seq_len, hidden)

                attention_mask = inputs['attention_mask'].unsqueeze(-1)  # (batch, seq_len, 1)
                masked_embeddings = token_embeddings * attention_mask

                summed = masked_embeddings.sum(dim=1)
                counts = attention_mask.sum(dim=1)
                embeddings = summed / counts  # average pooling

                embeddings = F.normalize(embeddings, p=2, dim=1)
                vectors = embeddings.detach().cpu().numpy()
                return vectors

    def ensure_model_loaded(self):
        self.model  # access model to trigger load

    def encode_passages(self, passages: list[str]):
        texts = [f"passage: {p}" for p in passages]
        return self.encode(texts)

    def encode_query(self, text: str):
        # "query: text" is the training query format
        # "passage: text" is the training document format
        return self._encode_text(f"query: {text}")

    def _encode_text(self, text: str):
        return self.encode([text])

    def get_shape(self) -> int:
        # Create a dummy vector to get dimensions
        # TODO! is this the best way to get this?
        #  should I just hardcode for now? (per model?)
        sample_text = "passage: sample"
        sample_vec = self._encode_text(sample_text)
        shape = sample_vec.shape[1]
        return shape

model_wrapper = ModelWrapper()
