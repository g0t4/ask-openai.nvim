from dataclasses import asdict, dataclass
import socket

from lsp.logs import get_logger
from lsp.inference.comms import *

logger = get_logger(__name__)

@dataclass
class RerankRequest:
    instruct: str
    query: str
    docs: list[str]
    type: str = "rerank"

class InferenceClient():

    def __init__(self):
        self.conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.addy = ("ollama.lan", 8015)

    def encode(self, inputs: dict[str, str]) -> list[list[float]] | None:
        # PRN add dataclass like rerank below
        inputs['type'] = 'embed'
        send_len_then_msg(self.conn, inputs)
        response = recv_len_then_msg(self.conn)
        if response is None:
            logger.warning(f"missing {response=}")
            return None

        # outer list is batch size
        # inner list is hidden dimension (vector size) of float - i.e. 1024 with Qwen3-Embedding-0.6B
        return response['embeddings']

    def rerank(self, request: RerankRequest) -> list[float] | None:
        send_len_then_msg(self.conn, asdict(request))
        response = recv_len_then_msg(self.conn)
        if response is None:
            logger.warning(f"missing {response=}")
            return None

        return response['scores']

    def close(self):
        self.conn.close()

    def __enter__(self):
        self.conn.connect(self.addy)
        return self

    def __exit__(self, _exc_type, _exc_value, _traceback):
        self.close()
