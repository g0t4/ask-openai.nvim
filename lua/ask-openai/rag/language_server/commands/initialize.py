import lsprotocol.types as types

from pygls import uris
from pygls.lsp.server import LanguageServer
from logs import get_logger
from index import workspace
from language_server.commands import update_file

logger = get_logger(__name__)

def setup(server: LanguageServer):

    @server.feature(types.INITIALIZE)
    async def on_initialize(_: LanguageServer, params: types.InitializeParams):
        # logger.inspect_info("params", params)
        logger.debug("LSP %s", params.client_info)

        folders = params.workspace_folders or []
        if not any(folders):
            message = "no workspace folders provided, cannot start ask_language_server"
            logger.error(message)
            raise ValueError(message)

        if len(folders) > 1:
            message = "only one workspace folder is currently supported"
            logger.error(message)
            raise ValueError(message)

        first_folder = folders[0]
        folder = uris.to_fs_path(first_folder.uri)
        assert folder is not None
        await workspace.from_folder(folder)

        if not workspace.get_config().enabled or workspace.is_no_rag_dir():
            logger.debug("RAG disabled or no .rag directory, skipping initialization")
            # DO NOT notify yet, that has to come after server responds to initialize request
            return types.InitializeResult(capabilities=types.ServerCapabilities())

        workspace.load_datasets()
        workspace.validate_datasets()

    def tell_client_to_shut_that_shit_down_now():
        server.protocol.notify("fuu/no_dot_rag__do_the_right_thing_wink")

    @server.feature(types.INITIALIZED)
    def on_initialized(_: LanguageServer, _params: types.InitializedParams):
        #  FYI server is managed by the client!
        #  client sends initialize request first => waits for server to send InitializeResult
        #    https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialize
        #  then, client sends initialized (this) request => waits for completion
        #    does not send other requests until initialized is done
        #  https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#initialized

        if not workspace.get_config().enabled:
            logger.info("RAG disabled, notifying LSP client to shutdown")
            tell_client_to_shut_that_shit_down_now()
            return

        if workspace.is_no_rag_dir():
            # TODO allow building the index from scratch?
            logger.error(f"STOP on_initialize[d] b/c no .rag dir")
            tell_client_to_shut_that_shit_down_now()
            return

        update_file.create_queue(server)
