from pathlib import Path
import sys
from lsp.storage import load_all_datasets, Datasets
from lsp.logs import get_logger, logging_fwk_to_console

logger = get_logger(__name__)

class DatasetsValidator:

    def __init__(self, datasets: Datasets):
        self.datasets = datasets
        self.any_problems = False

    def validate(self):

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
                    logger.error(f"Duplicate ID found: {id} with {count}x - {chunk.file} L{chunk.start_line}-{chunk.end_line}")

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

if __name__ == "__main__":
    # usage:
    #   python3 -m index.validate $(_repo_root)/.rag

    logging_fwk_to_console(level="DEBUG")

    rag_dir = Path(sys.argv[1])
    ds = load_all_datasets(rag_dir)

    validator = DatasetsValidator(ds)
    validator.validate()

    if validator.any_problems:
        sys.exit(1)
