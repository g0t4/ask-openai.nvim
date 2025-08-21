import rich

from lsp.logs import get_logger, logging_fwk_to_console
from lsp.remote.comms import *
from lsp.remote.retrieval import semantic_grep

def format_score_percent(score: float) -> str:
    """score as percentage rounded to nearest 4 decimals"""
    return f'{score * 100:.2f}%'

if __name__ == "__main__":

    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    # * instruct / task
    # FYI! sync any changes to instruct to the respective python re-ranking code
    query = "where did I set the top_k for semantic grep?"

    chunks = semantic_grep(query)

    # * dump details
    for idx, c in enumerate(chunks):
        rich.print(f'#{c.rerank_rank} / {c.chunk.id}: rerank={format_score_percent(c.rerank_score)} embed={format_score_percent(c.embed_score)}/#{c.embed_rank}')
        if logger.isEnabledForDebug():
            print(c.chunk.text)
