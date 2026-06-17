import asyncio
import rich
from pathlib import Path

from logs import get_logger, logging_fwk_to_console, print_code
from index.storage import load_all_datasets
from inference.client.retrieval import *
from index import workspace

def format_score_percent(score: float) -> str:
    """score as percentage rounded to nearest 4 decimals"""
    return f'{score * 100:.2f}%'

async def main():
    logging_fwk_to_console("INFO")
    # logging_fwk_to_console("DEBUG")
    logger = get_logger(__name__)

    dot_rag_dir = Path("~/repos/github/g0t4/ask-openai.nvim/.rag").expanduser().absolute()
    await workspace.set_folder(dot_rag_dir.parent)
    datasets = load_all_datasets(dot_rag_dir)

    args = LSPSemanticGrepRequest(
        query="where did I set the top_k for semantic grep?",
        currentFileAbsolutePath="test.py",
        vimFiletype="py",
        instruct=None,  # intentionally blank
        skipSameFile=False,
        topK=4,
        embedTopK=8,
        languages="EVERYTHING",  # test search across languages
    )

    ranked_matches = await semantic_grep(
        args=args,
        datasets=datasets,
    )

    # * dump details
    for idx, m in enumerate(ranked_matches):
        rich.print(f'#{m.rerank_rank} / {m.id}: rerank={format_score_percent(m.rerank_score)} embed={format_score_percent(m.embed_score)}/#{m.embed_rank}')
        if logger.isEnabledForDebug():
            print_code(m.text)

if __name__ == "__main__":
    asyncio.run(main())
