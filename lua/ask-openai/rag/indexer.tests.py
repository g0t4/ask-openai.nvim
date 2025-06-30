import json
from pathlib import Path
import subprocess
import unittest

import faiss
from rich import print

from indexer import IncrementalRAGIndexer

class TestBuildIndex(unittest.TestCase):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.rag_dir = Path(__file__).parent / "tests/.rag"
        self.rag_dir.mkdir(exist_ok=True, parents=True)
        self.source_dir = Path(__file__).parent / "tests" / "indexer_src"

    def trash_rag_dir(self):
        if self.rag_dir.exists():
            subprocess.run(["trash", self.rag_dir])

    def test(self):
        self.trash_rag_dir()
        indexer = IncrementalRAGIndexer(self.rag_dir, self.source_dir)
        indexer.build_index(language_extension="lua")

        chunks_json_path = self.rag_dir / "lua" / "chunks.json"
        print(f'{chunks_json_path=}')
        assert chunks_json_path.exists()

        files_json_path = self.rag_dir / "lua" / "files.json"
        print(f'{files_json_path=}')
        assert files_json_path.exists()

        vectors_index_path = self.rag_dir / "lua" / "vectors.index"
        print(f'{vectors_index_path=}')
        assert vectors_index_path.exists()

        with open(chunks_json_path, "r") as f:
            chunks = json.loads(f.read())
            assert len(chunks) == 3  # 41 lines currently, 5 overlap + 20 per chunk
            sample_lua_path = (self.source_dir / "sample.lua").absolute()
            print(f'{sample_lua_path=}')
            for c in chunks:
                self.assertEqual(c["file"], str(sample_lua_path))

            first_chunk = [c for c in chunks if c["start_line"] == 1][0]
            self.assertEqual(first_chunk["start_line"], 1)
            self.assertEqual(first_chunk["end_line"], 20)
            self.assertEqual(len(first_chunk["text"].split("\n")), 18)

            second_chunk = [c for c in chunks if c["start_line"] == 16][0]
            self.assertEqual(second_chunk["start_line"], 16)
            self.assertEqual(second_chunk["end_line"], 35)

            third_chunk = [c for c in chunks if c["start_line"] == 31][0]
            self.assertEqual(third_chunk["start_line"], 31)
            self.assertEqual(third_chunk["end_line"], 41)

        with open(files_json_path, "r") as f:
            contents = json.loads(f.read())
            assert len(contents) == 1
            file_meta = contents[str(sample_lua_path)]

            # sha256sum /Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/tests/indexer_src/sample.lua | cut -d ' ' -f1
            self.assertEqual(file_meta["hash"], "b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b")
            # PRN get rid of redundancy in path? already key
            self.assertEqual(file_meta["path"], str(sample_lua_path))
            # how do I assert the timestamp is at least reasonable?
            self.assertTrue(file_meta["mtime"] > 1735711201)  # Jan 1 2025 00:00:00 UTC - before this code existed :)
            # cat tests/indexer_src/sample.lua | wc -c
            self.assertEqual(file_meta["size"], 1_173)

        # verify 3 vectors
        # https://faiss.ai/cpp_api/struct/structfaiss_1_1IndexFlatIP.html
        index = faiss.read_index(str(vectors_index_path))
        assert index.ntotal == 3  # 41 lines currently, 5 overlap + 20 per chunk
        print(f'{index=}')
        # assert index.ntotal == len(chunks)

        # assert "chunks" in contents
        # assert "text" in contents
        # assert "metadata" in contents

if __name__ == "__main__":
    unittest.main()
