from dataclasses import dataclass
from .logs import get_logger

logger = get_logger(__name__)

with logger.timer("importing sentence transformers"):
    from sentence_transformers import SentenceTransformer

@dataclass
class ModelWrapper:
    model: SentenceTransformer

# TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model
model_name = "intfloat/e5-base-v2"
with logger.timer(f"Load model {model_name}"):
    st_model = SentenceTransformer(model_name)
    model = ModelWrapper(st_model)
