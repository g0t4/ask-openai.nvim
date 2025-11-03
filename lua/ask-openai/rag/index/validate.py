from pathlib import Path
import subprocess
import sys
from lsp.storage import load_all_datasets, Datasets
from lsp.logs import get_logger, logging_fwk_to_console
import os
from collections import Counter
from typing import Set

logger = get_logger(__name__)

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
            logger.debug("[bold green]ALL CHECKS PASS!")

    def warn_about_unindexed_languages(self, datasets: Datasets) -> None:

        def find_extensions_in_cwd():
            fd_command = ["fd", "--type", "file"]  # `fd` respects ignores
            out = subprocess.check_output(fd_command, text=True)
            # PRN git ls-files or other fallback

            extension_counts = Counter()
            for file_path in out.splitlines():
                extension = Path(file_path).suffix.lower().lstrip(".")
                if extension:
                    extension_counts[extension] += 1
            return extension_counts

        extension_counts = find_extensions_in_cwd()

        EXTENSION_COUNT_THRESHOLD = 10
        frequent_extensions = {extension for extension, count in extension_counts.items() if count > EXTENSION_COUNT_THRESHOLD}
        indexed_extensions = datasets.get_indexed_extensions()
        missing_extensions = frequent_extensions - indexed_extensions
        # ? split into rag.yaml ignored vs just not indexed at all (two prints?)

        if missing_extensions:
            missing_counts = {extension: extension_counts[extension] for extension in missing_extensions}
            logger.debug("Found prominent, unindexed extensions: " + ", ".join( \
                f"{extension}={count}" for extension, count in missing_counts.items()))
        else:
            logger.debug("All good, no missing extensions, you lucky motherf***er")

def main():
    # usage:
    #   python3 -m index.validate $(_repo_root)/.rag

    logging_fwk_to_console(level="DEBUG")

    rag_dir = Path(sys.argv[1])
    ds = load_all_datasets(rag_dir)

    validator = DatasetsValidator(ds)
    validator.validate_datasets()

    validator.warn_about_unindexed_languages(ds)

    if validator.any_problems:
        sys.exit(1)

if __name__ == "__main__":
    main()
