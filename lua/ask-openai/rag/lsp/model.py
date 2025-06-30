from logs import LogTimer

with LogTimer("importing sentence transformers"):
    from sentence_transformers import SentenceTransformer

# TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model
model_name = "intfloat/e5-base-v2"
with LogTimer(f"Load model {model_name}"):
    model = SentenceTransformer(model_name)
