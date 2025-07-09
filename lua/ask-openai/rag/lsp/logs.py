import logging
import os
import time
from typing import cast

from rich.console import Console
from rich.logging import RichHandler
from rich.pretty import pretty_repr

logging.getLogger("pygls.protocol.json_rpc").setLevel(logging.WARN)  # DEBUG messages on every message!
logging.getLogger("pygls.protocol.language_server").setLevel(logging.WARN)  # server capabilities on startup
logging.getLogger("pygls.feature_manager").setLevel(logging.WARN)  # what features are registered/detected
logging.getLogger("pygls.server").setLevel(logging.WARN)  # mostly Content length messages (headers IIAC)

# TODO use verbose flag to toggle on DEBUG/INFO messages?
# does nvim have a setting that is used across LS's that I can somehow have passed besides obviously just adding to my own config somewhere?

log_file_path = os.path.expanduser("~/.local/share/ask-openai/language.server.log")
log_file = open(log_file_path, "w", encoding="utf-8")
# logging.basicConfig(filename=log_file, level=logging.DEBUG)
console = Console(file=log_file, force_terminal=True, width=150)
# TODO how can I get rich to not add wraps on long lines... width=None still wraps
hand = RichHandler(
    markup=True,  # i.e. [bold], [red]
    rich_tracebacks=True,
    console=console,
    show_path=False,
    show_time=False,
)

format = "%(asctime)s %(name)s: %(message)s"
# %(asctime)s
logging.basicConfig(
    level="NOTSET",
    format=format,
    datefmt="[%X]",
    handlers=[hand],
)

class Logger(logging.Logger):

    def pp(self, obj):
        return pretty_repr(obj, indent_size=2)

    def pp_info(self, message, obj):
        self.info(f"{message}: %s", self.pp(obj))

    def timer(self, finished_message=""):
        return LogTimer(finished_message, logger=self)

def get_logger(name) -> Logger:
    logging.setLoggerClass(Logger)
    logger = cast(Logger, logging.getLogger(name))
    return logger

# by the way will have FQN, which how I run this is lsp.logs for this module
generic_logger = get_logger(__name__)

class LogTimer:

    def __init__(self, finished_message="", logger=None):
        self.logger = logger or generic_logger
        self.finished_message = finished_message

    def __enter__(self):
        self.start_ns = time.time_ns()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.end_ns = time.time_ns()
        elapsed_ns = self.end_ns - self.start_ns
        elapsed_ms = elapsed_ns / 1000000
        self.logger.info(f"{self.finished_message}: {elapsed_ms:,.2f} ms")
