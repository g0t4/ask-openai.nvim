import logging
import os
import time

from rich.console import Console
from rich.logging import RichHandler

logging.getLogger("pygls.protocol.json_rpc").setLevel(logging.WARN)  # hide DEBUG messages
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

class LogTimer:

    def __init__(self, finished_message=""):
        self.finished_message = finished_message

    def __enter__(self):
        self.start_ns = time.time_ns()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.end_ns = time.time_ns()
        elapsed_ns = self.end_ns - self.start_ns
        elapsed_ms = elapsed_ns / 1000000
        logging.info(f"wall time ({self.finished_message}): {elapsed_ms:,.2f} ms")
