from pathlib import Path

from index.storage import Datasets, load_all_datasets

# TODO THIS MODULE DOES NOT NEED TO EXIST, just PASS Datasets (or some object with it on it, maybe RagProject == Datasets + Config?)
datasets: Datasets

def load_model_and_indexes(dot_rag_dir: Path):
    global datasets
    datasets = load_all_datasets(dot_rag_dir)
