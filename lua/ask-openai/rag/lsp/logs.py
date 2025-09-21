import logging
import time
from typing import cast
from pathlib import Path

from rich.console import Console
from rich.logging import RichHandler
from rich.pretty import pretty_repr

logging.getLogger("pygls.protocol.json_rpc").setLevel(logging.WARN)  # DEBUG messages on every message!
logging.getLogger("pygls.protocol.language_server").setLevel(logging.WARN)  # server capabilities on startup
logging.getLogger("pygls.feature_manager").setLevel(logging.WARN)  # what features are registered/detected
logging.getLogger("pygls.server").setLevel(logging.WARN)  # mostly Content length messages (headers IIAC)
logging.getLogger("asyncio").setLevel(logging.WARN)  # mostly Content length messages (headers IIAC)

def setup_logging(console: Console, level=logging.WARN):
    rich_handler = RichHandler(
        markup=True,  # i.e. [bold], [red]
        rich_tracebacks=True,
        console=console,
        show_path=False,
        show_time=False,
    )
    handlers = [rich_handler]

    format = "%(asctime)s %(name)s: %(message)s"
    logging.basicConfig(
        level=level,
        format=format,
        datefmt="[%X]",
        handlers=handlers,
        force=True,  # force override root logger, in part to undo pytest hijacking root logger
    )

def clear_iterm_scrollback(log_file):
    # FYI some imports take time and will delay this happening for a few seconds (i.e. model load on import)
    # * clear iTerm scrollback/screen!
    #   \x1b = ESC (ansi escape sequence start)
    #   ESC] = Operating System Command
    #   50 and 1337 both work
    #     iTerm docs recommend 1337 to avoid conflicts w/ xterm (origin of many of these commands)
    #
    # https://iterm2.com/documentation-escape-codes.html

    # see: https://apple.stackexchange.com/a/382057/53333
    # clear_iterm_scrolback = "\x1b]50;ClearScrollback\a"
    clear_iterm_scrolback = "\x1b]1337;ClearScrollback\a"
    log_file.write(clear_iterm_scrolback)
    log_file.flush()
    #
    # * clear just current screen using rich (through log works):
    # console.clear()  # NOTE: not scrollback in iTerm (obviously)
    # TODO does console have a clear scrollback too that blasts all possible clears? or that I can specific which term to do it for?

def logging_fwk_to_language_server_log_file(level):

    log_file_path = Path("~/.local/share/ask-openai/language.server.log").expanduser()
    log_file_path.parent.mkdir(parents=True, exist_ok=True)

    log_file = open(log_file_path, "w", encoding="utf-8")
    console = Console(file=log_file, force_terminal=True, width=150)

    clear_iterm_scrollback(log_file)

    setup_logging(console, level)

def logging_fwk_to_console(level):
    console = Console()
    setup_logging(console, level)

class Logger(logging.Logger):

    def _pp(self, obj):
        return pretty_repr(obj, indent_size=2)

    def pp_info(self, message, obj):
        if not self.isEnabledFor(logging.INFO):
            return
        self.info(f"{message}: %s", self._pp(obj))

    def pp_debug(self, message, obj):
        if not self.isEnabledFor(logging.DEBUG):
            return
        self.debug(f"{message}: %s", self._pp(obj))

    def timer(self, finished_message=""):
        return LogTimer(finished_message, logger=self)

    def isEnabledForDebug(self):
        # for when the calling code is unavoidably expensive
        return self.isEnabledFor(logging.DEBUG)

    def isEnabledForInfo(self):
        return self.isEnabledFor(logging.INFO)

    def dump_sentence_transformers_model(self, model: "SentenceTransformer"):
        if not self.isEnabledFor(logging.DEBUG):
            return

        self.debug(f'Modules: %r', model.modules)
        auto_model = model._first_module().auto_model
        self.debug(f"auto_model: %r", auto_model)
        self.debug(f"auto_model.dtype: [bold red]%s", auto_model.dtype)

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

class Timer:

    def __enter__(self):
        self.start_ns = time.time_ns()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.end_ns = time.time_ns()

    def elapsed_ns(self):
        return self.end_ns - self.start_ns

    def elapsed_ms(self):
        return self.elapsed_ns() / 1000000

DISABLE_PRINT_TMP = False

def disable_printtmp():
    # by the way disabling it means when I am using the printtmp for unit tests,
    # I can run LS and indexer CLI and not need to have them blow up and/or insane logs there
    #   then I comment out printtmp calls when done, and they are easier to spot now that they're called printtmp (to uncomment later when testing again and need them)
    global DISABLE_PRINT_TMP
    DISABLE_PRINT_TMP = True

# force color, for pytest/ptw runners
console = Console(force_terminal=True)

# mostly for STDOUT when running pytest
# sometimes I use this for rag_indexer too
# intended for temporary use
# stuff I might comment out when I am done too, not just drop log level
def printtmp(what):
    if DISABLE_PRINT_TMP:
        return

    console.print(what)
