import logging
import os
import signal

import lsprotocol.types as types
from pygls.lsp.server import LanguageServer
from pygls.protocol.json_rpc import MsgId

from index import fs
from language_server import rag
from rag.logs import get_logger, logging_fwk_to_language_server_log_file
from language_server.commands import sleepy, grep, update_file
from language_server.stoppers import request_stop

logging_fwk_to_language_server_log_file(logging.INFO)
# logging_fwk_to_language_server_log_file(logging.DEBUG)
logger = get_logger(__name__)

server = LanguageServer("ask_language_server", "v0.1")

original__handle_cancel_notification = server.protocol._handle_cancel_notification

def _trigger_stopper_on_cancel(msg_id: MsgId):
    if request_stop(msg_id):
        logger.info(f'triggered stopper {msg_id=}')
        return

    # logger.info(f"fallback to original__handle_cancel_notification {msg_id}")
    original__handle_cancel_notification(msg_id)

server.protocol._handle_cancel_notification = _trigger_stopper_on_cancel

sleepy.register_command(server)
update_file.register_commands(server)
grep.register_command(server)

@server.feature(types.INITIALIZE)
async def on_initialize(_: LanguageServer, params: types.InitializeParams):
    # TODO pass rag dir as command line arg??
    # - TODO so I don't have to wait for on_initialize to setup Datasets!

    # # PRN use workspace folders if multi-workspace ...
    # # FYI could also get me CWD, round about way, if I wanted to prioritize that for .rag dir over git repo root
    # logger.info(f"{params.workspace_folders=}")
    # server.workspace.folders

    await fs.set_root_dir(params.root_path)
    if not fs.get_config().enabled or fs.is_no_rag_dir():
        # DO NOT notify yet, that has to come after server responds to initialize request
        return types.InitializeResult(capabilities=types.ServerCapabilities())

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

    if not fs.get_config().enabled:
        logger.info("RAG disabled, notifying LSP client to shutdown")
        tell_client_to_shut_that_shit_down_now()
        return

    if fs.is_no_rag_dir():
        # TODO allow building the index from scratch?
        logger.error(f"STOP on_initialize[d] b/c no .rag dir")
        tell_client_to_shut_that_shit_down_now()
        return

    rag.load_model_and_indexes(fs.rag_project.dot_rag_dir)  # TODO! ASYNC?
    rag.validate_rag_indexes()  # TODO! ASYNC?
    update_file.create_queue(server)

def sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS(*_):
    logger.warning("SIGKILL myself")
    os.kill(os.getpid(), signal.SIGKILL)

# TODO detect when LSP disconnects and shutdown self?

signal.signal(signal.SIGINT, sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS)

server.start_io()
