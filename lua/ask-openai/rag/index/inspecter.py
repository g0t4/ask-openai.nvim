from pathlib import Path
import sys
from indexer import load_prior_data
from lsp.logs import get_logger, logging_fwk_to_console

logger = get_logger(__name__)
logging_fwk_to_console(level="DEBUG")

rag_dir = Path(sys.argv[1])
dataset = load_prior_data(rag_dir, "py")
