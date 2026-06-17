import asyncio
import os
import rich
import subprocess
import sys
import humanize

from collections import Counter
from pathlib import Path
from typing import Set
from logs import get_logger, logging_fwk_to_console
from index.storage import load_all_datasets, Datasets
from chunks.chunker import get_file_stat
from index import workspace

from config.domains import resolve_semantic_domain
from index.stale import warn_about_stale_files

logger = get_logger("validator")

class DatasetsValidator:

    def __init__(self, datasets: Datasets):
        self.datasets = datasets
        self.any_problems = False

    def validate_datasets(self):
        for dataset in self.datasets.all_datasets.values():
            any_problem_with_this_dataset = False

            # * compare # vectors to # IDs
            num_vectors_based_on_ntotal = dataset.index_view.num_vectors()
            ids = dataset.index_view.ids
            if len(ids) != num_vectors_based_on_ntotal:
                logger.error(f"{len(ids)=} != {num_vectors_based_on_ntotal=}")
                any_problem_with_this_dataset = True

            # * test for duplicate IDs
            duplicate_ids = list(dataset.index_view._check_for_duplicate_ids())
            for id, count in duplicate_ids:
                if count <= 1:
                    continue
                any_problem_with_this_dataset = True
                chunk = self.datasets.get_chunk_by_faiss_id(id)
                if chunk is None:
                    logger.error(f"Duplicate ID found: {id} - {count}x - missing chunk too")
                else:
                    logger.error(f"Duplicate ID found: {id} with {count}x - {chunk.file} L{chunk.base0.start_line}-{chunk.base0.end_line}")

            # * compare chunk counts vs ID counts
            num_unique_ids_based_on_ids = len(duplicate_ids)
            num_chunks_based_on_chunks = sum([len(file) for file in dataset.chunks_by_file.values()])

            if num_unique_ids_based_on_ids != num_chunks_based_on_chunks:
                any_problem_with_this_dataset = True
                logger.error(f"chunk count mismatch: {num_unique_ids_based_on_ids=} != {num_chunks_based_on_chunks=}")

            num_vectors_based_on_ids = sum([count for _, count in duplicate_ids])
            if num_vectors_based_on_ntotal != num_vectors_based_on_ids:
                any_problem_with_this_dataset = True
                logger.error(f"vectors count mismatch: {num_vectors_based_on_ntotal=} != {num_vectors_based_on_ids=}")

            if any_problem_with_this_dataset:
                logger.info(f"{num_vectors_based_on_ntotal=}")

                # look for mismatch in datasets (i.e. missing chunks or vectors for old chunks)
                logger.info(f'{num_vectors_based_on_ids=} {num_unique_ids_based_on_ids=}')
                logger.info(f'{num_chunks_based_on_chunks=}')

            self.any_problems = self.any_problems or any_problem_with_this_dataset

        if self.any_problems:
            logger.error("[bold red]AT LEAST ONE PROBLEM DISCOVERED")
        else:
            logger.info("[bold green]ALL CHECKS PASS!")

    def warn_about_unindexed_domains(self, datasets: Datasets) -> None:
        """Warn about semantic domains with many files that aren't indexed."""

        def find_domains_in_cwd():
            fd_command = ["fd", "--type", "file"]
            out = subprocess.check_output(fd_command, text=True)

            domain_counters = Counter()
            for file_path in out.splitlines():
                domain = resolve_semantic_domain(file_path)
                if domain:
                    domain_counters[domain] += 1
            return domain_counters

        domain_counts = find_domains_in_cwd()

        EXTENSION_COUNT_THRESHOLD = 10
        frequent_domains = {domain for domain, count in domain_counts.items() if count > EXTENSION_COUNT_THRESHOLD}
        indexed_domains = set(datasets.all_datasets.keys())
        missing_domains = frequent_domains - indexed_domains

        if missing_domains:
            missing_counts = {domain: domain_counts[domain] for domain in missing_domains}
            logger.debug("Found prominent, unindexed semantic domains: " + ", ".join( \
                f"{ft}={count}" for ft, count in missing_counts.items()))
        else:
            logger.debug("All good, no missing semantic domains, you lucky motherf***er")

    def compare_config_vs_indexed_domains(self, datasets: Datasets, config: workspace.RagConfig) -> None:
        """Compare configured semantic domains against what's actually indexed on disk."""

        present_domains = set(datasets.all_datasets.keys())
        configured_domains = set(config.allowed_semantic_domains)

        extra_domains = present_domains - configured_domains
        if extra_domains:
            self.any_problems = True
            logger.error( \
                "[bold white on red]Vestigial datasets (semantic domains that aren't indexed): "
                + ", ".join(sorted(extra_domains))
            )

        missing_domains = configured_domains - present_domains
        if missing_domains:
            self.any_problems = True
            logger.error( \
                "[bold white on red]Missing datasets (configured semantic domains): "
                + ", ".join(sorted(missing_domains))
            )

async def main():
    # usage:
    #   python3 -m index.validate $(_repo_root)/.rag

    logging_fwk_to_console(level="DEBUG")

    dot_rag_dir = Path(sys.argv[1])
    workspace_folder = dot_rag_dir.parent
    await workspace.from_folder(workspace_folder)
    workspace.load_datasets()

    # explicit calls to validate b/c that's what this module does! don't use this via workspace.validate_datasets()
    validator = DatasetsValidator(workspace.datasets)
    validator.validate_datasets()
    validator.warn_about_unindexed_domains(workspace.datasets)

    warn_about_stale_files(workspace.datasets, workspace_folder)

    config = await workspace.load_rag_config(workspace_folder)
    validator.compare_config_vs_indexed_domains(workspace.datasets, config)

    if validator.any_problems:
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
