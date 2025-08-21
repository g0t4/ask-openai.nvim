import rich

from lsp.logs import get_logger, logging_fwk_to_console
from lsp.remote.comms import *
from lsp.remote.retrieval import *

def format_score_percent(score: float) -> str:
    """score as percentage rounded to nearest 4 decimals"""
    return f'{score * 100:.2f}%'

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    test_query = "where did I set the top_k for semantic grep?"
    ranked_matches = semantic_grep(
        query=test_query,
        current_file_abs="test.py",
        vim_filetype="py",
        instruct=None,  # intentionally blank
        skip_same_file=False,
        top_k=20,
    )

    # * dump details
    for idx, m in enumerate(ranked_matches):
        rich.print(f'#{m.rerank_rank} / {m.id}: rerank={format_score_percent(m.rerank_score)} embed={format_score_percent(m.embed_score)}/#{m.embed_rank}')
        if logger.isEnabledForDebug():
            print(m.text)
