from asyncio import open_connection
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

class AsyncInferenceClient:

    async def disconnect(self):
        self.writer.close()
        await self.writer.wait_closed()

    async def signal_hotpath_done(self) -> None:
        logger.info("signaling hotpath done")
        message = {'type': 'hotpath_done'}
        await send_len_then_msg_async(self.writer, message)
        # no response

    async def encode(self, inputs: dict[str, str]) -> list[list[float]] | None:
        # PRN add dataclass like rerank below
        inputs['type'] = 'embed'
        await send_len_then_msg_async(self.writer, inputs)
        response = await recv_len_then_msg_async(self.reader)
        if response is None:
            logger.warning("empty response, disconnecting")
            return await self.disconnect()

        # outer list is batch size
        # inner list is hidden dimension (vector size) of float - i.e. 1024 with Qwen3-Embedding-0.6B
        return response['embeddings']

    async def rerank(self, request: RerankRequest) -> list[float] | None:
        await send_len_then_msg_async(self.writer, asdict(request))
        response = await recv_len_then_msg_async(self.reader)
        if response is None:
            logger.warning("empty response, disconnecting")
            return await self.disconnect()

        return response['scores']

    async def __aenter__(self):
        self.reader, self.writer = await open_connection(
            host="ollama.lan",
            port=8015,
            family=socket.AF_INET,
        )
        return self

    async def __aexit__(self, _exc_type, _exc, _tb):
        await self.disconnect()
