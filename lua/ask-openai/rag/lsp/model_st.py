import os

# FYI! this was prior to remote qwen3 AND also prior to not using SenteceTransformers
#  I cannot recall but I might need ST for intfloat/e5-base-v2... not sure
# for now I want to use Qwen3 and remote
# so I am retiring this file, especially b/c its not imported anywhere

from .logs import get_logger

logger = get_logger(__name__)

_model = None
_model_name = ""  # only meant for reading internally

def ensure_model_loaded():
    global _model, _model_name
    if _model:
        return _model

    with logger.timer("import torch"):
        # FYI pre-load so timing is never skewed on encode
        import torch

    with logger.timer("importing sentence transformers"):

        # do not check hugging face for newer version, use offline cache only
        #   550ms load time vs 1200ms for =>    model = SentenceTransformer(model_name)
        # FYI must be set BEFORE importing SentenceTransformer, setting after (even if before model load) doesn't work
        os.environ["TRANSFORMERS_OFFLINE"] = "1"

        from sentence_transformers import SentenceTransformer  # 2+ seconds to import (mostly torch/transformer deps that even if I use BertModel directly, I cannot avoid the import timing)

    # TODO try Alibaba-NLP/gte-base-en-v1.5 ...  for the embeddings model
    def use_intfloat_e5_base():
        # TODO find some test data to validate embeddings are properly calculated!
        _model_name = "intfloat/e5-base-v2"
        _model = SentenceTransformer(_model_name,
                                     # TODO set dtype auto/float16/etc?
                                     # model_kwargs={"torch_dtype": "float16"},
                                     )
        return _model

    def use_qwen3():
        # PRN add startup validation of embeddings calculations and params from auto model
        _model_name = "Qwen/Qwen3-Embedding-0.6B"
        return SentenceTransformer(
            _model_name,
            model_kwargs={
                "torch_dtype": "float16",
                # "device_map": "auto", # for sharding
            },  # else float32 which RUINs perf and outputs! on both CUDA and MPS backends
        )

    with logger.timer(f"Loaded model"):
        _model = use_intfloat_e5_base()
        # _model = use_qwen3()

    logger.dump_sentence_transformers_model(_model)

    return _model

def _encode_multiple(texts):
    import torch

    # from pympler import asizeof
    # texts_bytes = asizeof.asizeof(texts)

    # set batch_size high to disable batching if that is better perf on the 5090s
    #   added batching to investigate issues w/ qwen3 on mac w/ ST and the memory explosion (even after disable autograd!)
    def batched_encode(texts, batch_size=8):
        # FYI! qwen3 works fine now with ST! with small batch size too!
        all_vecs = []
        with torch.no_grad():
            total = len(texts)
            for i in range(0, total, batch_size):
                logger.info(f"    batch {i}-{i+batch_size} of {total}")
                batch = texts[i:i + batch_size]
                vecs = ensure_model_loaded().encode(
                    batch,
                    normalize_embeddings=True,
                    show_progress_bar=False,
                    convert_to_tensor=True,
                )
                all_vecs.append(vecs.cpu())  # move to CPU to free GPU/MPS memory, s/b sub 1ms overhead

        return torch.cat(all_vecs, dim=0)

    vecs_np = batched_encode(texts)

    # size_bytes = asizeof.asizeof(vecs_np)
    logger.info(f"  done encoding")  #  - {type(vecs_np)=} size_bytes={size_bytes} {vecs_np.shape=}")

    return vecs_np

def encode_passages(passages: list[str]):
    texts = [f"passage: {p}" for p in passages]
    return _encode_multiple(texts)

def encode_query(text: str, instruct: str):
    # if not Qwen3 then raise if instructions passed
    if instruct is not None and instruct != "":
        if not _model_name.startswith("Qwen/Qwen3-Embedding"):
            raise ValueError("Qwen3 is required for econding instructions into embeddings query")
        # see impl in model_Qwen3 alternatives...
        raise NotImplementedError("TODO I am not planning to use Qwen3 with in-process SentenceTransformers, you'll have to set this up if you want it")

    # "query: text" is the training query format
    # "passage: text" is the training document format
    return _encode_one_text(f"query: {text}")

def _encode_one_text(text: str):
    return _encode_multiple([text])

def get_shape() -> int:
    # Create a dummy vector to get dimensions
    sample_text = "passage: sample"
    sample_vec = _encode_one_text(sample_text)
    shape = sample_vec.shape[1]
    return shape
