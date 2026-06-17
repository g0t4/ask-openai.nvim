import attrs
import asyncio
from pygls.lsp.server import LanguageServer

from rag.logs import get_logger
from language_server.stoppers import Stopper, create_stopper, remove_stopper
from inference.client.retrieval import semantic_grep, LSPSemanticGrepRequest
from index.validate import DatasetsValidator
from index import fs
from language_server import rag

logger = get_logger(__name__)

@attrs.define
class LSPSemanticGrepResult:
    """ Either return matches OR an error string, nothing else matters."""
    matches: list = []
    error: str | None = None

class LSPResponseErrors:
    NO_RAG_DIR = "No .rag dir"
    CANCELLED = "Client cancelled query"

def setup(server: LanguageServer):

    @server.command("semantic_grep")
    async def semantic_grep_command(_: LanguageServer, args: LSPSemanticGrepRequest) -> LSPSemanticGrepResult:
        # return LSPSemanticGrepResult(error="FUUUU") # test server errors
        args.msgId = server.protocol.msg_id
        try:
            return await grep_command(args)  # TODO! ASYNC REVIEW
        except asyncio.CancelledError as e:
            # avoid leaving on in logs b/c takes up a ton of space for stack trace
            logger.debug(f"Client cancelled semantic_grep query {args.msgId=}")  #, exc_info=e)  # uncomment to see where error is raised
            return LSPSemanticGrepResult(error=LSPResponseErrors.CANCELLED)

async def grep_command(args: LSPSemanticGrepRequest) -> LSPSemanticGrepResult:

    stopper = create_stopper(args.msgId)
    try:
        if fs.is_no_rag_dir():
            return LSPSemanticGrepResult(error=LSPResponseErrors.NO_RAG_DIR)

        if args.query is None or len(args.query) == 0:
            logger.info("No query provided")
            return LSPSemanticGrepResult(error="No query provided")

        stopper.throw_if_stopped()

        # TODO REVIEW ASYNC (i.e. for file ops? or other async capable ops)
        matches = await semantic_grep(
            args=args,
            datasets=rag.datasets,
            stopper=stopper,
        )

        return LSPSemanticGrepResult(matches=matches)
    finally:
        remove_stopper(args.msgId)
