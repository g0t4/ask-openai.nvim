import logging
import os
import signal

import lsprotocol.types as types
from pygls.lsp.server import LanguageServer

# from index import fs # TODO setup the RagConfig/RagProject here with server setup, keep it as a global and pass to setup/register_command(s) of other modules
from rag.logs import get_logger, logging_fwk_to_language_server_log_file
from language_server.commands import sleepy, grep, update_file, cancel, initialize

logging_fwk_to_language_server_log_file(logging.INFO)
# logging_fwk_to_language_server_log_file(logging.DEBUG)
logger = get_logger(__name__)

server = LanguageServer("ask_language_server", "v0.1")

cancel.setup(server)
initialize.setup(server)
sleepy.setup(server)
update_file.setup(server)
grep.setup(server)

def sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS(*_):
    logger.warning("SIGKILL myself")
    os.kill(os.getpid(), signal.SIGKILL)

# TODO detect when LSP disconnects and shutdown self?

signal.signal(signal.SIGINT, sigkill_self_else_pygls_hangs_when_test_standalone_startup_of_LS)

server.start_io()
