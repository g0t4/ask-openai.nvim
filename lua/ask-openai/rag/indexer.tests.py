import json
from pathlib import Path
import subprocess
import unittest

from indexer import IncrementalRAGIndexer

class TestBuildIndex(unittest.TestCase):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.rag_dir = Path(__file__).parent / "tests/.rag"
        self.rag_dir.mkdir(exist_ok=True, parents=True)

    def setUp(self):
        if self.rag_dir.exists():
            subprocess.run(["trash", self.rag_dir])

    def test(self):
        indexer = IncrementalRAGIndexer(self.rag_dir)
        indexer.build_index(language_extension="lua")

        chunks_json = self.rag_dir / "lua" / "chunks.json"
        print(f'{chunks_json=}')
        assert chunks_json.exists()

        files_json = self.rag_dir / "lua" / "files.json"
        print(f'{files_json=}')
        assert files_json.exists()

        with open(chunks_json, "r") as f:
            contents = f.read()
            chunks = json.loads(contents)
            assert len(chunks) > 0

            # assert "chunks" in contents
            # assert "text" in contents
            # assert "metadata" in contents

if __name__ == "__main__":
    unittest.main()
