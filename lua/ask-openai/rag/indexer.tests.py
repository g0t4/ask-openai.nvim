import json
from pathlib import Path
import subprocess
import unittest

import faiss
import numpy as np
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

    def get_vector_index(self):
        vectors_index_path = self.rag_dir / "lua" / "vectors.index"
        print(f'{vectors_index_path=}')
        assert vectors_index_path.exists()
        index = faiss.read_index(str(vectors_index_path))
        return index

    def get_chunks(self):
        chunks_json_path = self.rag_dir / "lua" / "chunks.json"
        print(f'{chunks_json_path=}')
        assert chunks_json_path.exists()
        with open(chunks_json_path, "r") as f:
            return json.loads(f.read())

    def get_files(self):
        files_json_path = self.rag_dir / "lua" / "files.json"
        print(f'{files_json_path=}')
        assert files_json_path.exists()
        with open(files_json_path, "r") as f:
            return json.loads(f.read())

    def test(self):

        # * recreate index
        self.trash_rag_dir()
        indexer = IncrementalRAGIndexer(self.rag_dir, self.source_dir)
        indexer.build_index(language_extension="lua")

        # * chunks
        chunks = self.get_chunks()
        assert len(chunks) == 3  # 41 lines currently, 5 overlap + 20 per chunk
        sample_lua_path = (self.source_dir / "sample.lua").absolute()
        print(f'{sample_lua_path=}')
        for c in chunks:
            self.assertEqual(c["file"], str(sample_lua_path))
            self.assertEqual(c["type"], "lines")

        first_chunk = [c for c in chunks if c["start_line"] == 1][0]
        self.assertEqual(first_chunk["start_line"], 1)
        self.assertEqual(first_chunk["end_line"], 20)
        self.assertEqual(len(first_chunk["text"].split("\n")), 18)
        start = "local TestRunner = {}"
        self.assertEqual(first_chunk["text"].startswith(start), True)
        end = "table.insert(self.results, {status = \"fail\", message = \"Test failed: expected \" .. tostring(test.expected) .. \", got \" .. tostring(result)})"
        self.assertEqual(first_chunk["text"].endswith(end), True)
        # manually computed when running on my machine... so maybe warn if not same path
        # echo -n "/Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/tests/indexer_src/sample.lua:lines:1-20:b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b" | sha256sum | head -c16
        self.assertEqual(first_chunk["id"], "a5a168c50041e5ab")
        # bitmaths 0xa5a168c50041e5ab # but then  have to drop 64th bit (if set)=> bitmath => wc = do again if 64th was set and then use that value (last 63 bits of int64)
        self.assertEqual(first_chunk["id_int"], "2711563645975913899")

        second_chunk = [c for c in chunks if c["start_line"] == 16][0]
        self.assertEqual(second_chunk["start_line"], 16)
        self.assertEqual(second_chunk["end_line"], 35)

        third_chunk = [c for c in chunks if c["start_line"] == 31][0]
        self.assertEqual(third_chunk["start_line"], 31)
        self.assertEqual(third_chunk["end_line"], 41)

        # * files
        files = self.get_files()
        assert len(files) == 1
        file_meta = files[str(sample_lua_path)]

        # sha256sum /Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/tests/indexer_src/sample.lua | cut -d ' ' -f1
        self.assertEqual(file_meta["hash"], "b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b")
        # PRN get rid of redundancy in path? already key
        self.assertEqual(file_meta["path"], str(sample_lua_path))
        # how do I assert the timestamp is at least reasonable?
        self.assertTrue(file_meta["mtime"] > 1735711201)  # Jan 1 2025 00:00:00 UTC - before this code existed :)
        # cat tests/indexer_src/sample.lua | wc -c
        self.assertEqual(file_meta["size"], 1_173)

        # * vectors
        # https://faiss.ai/cpp_api/struct/structfaiss_1_1IndexFlatIP.html
        index = self.get_vector_index()

        self.assertEqual(index.ntotal, 3)
        self.assertEqual(index.d, 768)
        print(f'{index=}')
        # print(f'{index.metric_type=}')
        # print(f'{index.metric_arg=}')
        # print(f'{index.is_trained=}')
        for i in range(index.ntotal):
            print(i)

    def ignore_test_encode_integration_exploratory(self):
        from lsp.model import model
        q = model.encode(["hello"], normalize_embeddings=True)
        print(f'{q.shape=}')
        # currently hard coded model:
        # https://huggingface.co/intfloat/e5-base-v2
        # This model has 12 layers and the embedding size is 768.
        self.assertEqual(q.shape, (1, 768))

        index = self.get_vector_index()
        distances, indices = index.search(q, 3)
        print(f"{distances=}")
        print(f"{indices=}")
        # first two id_ints here have the hello world, last doesn't
        expected = np.array([[5737032561938488959, 7876391420168697139, 2711563645975913899]])
        np.testing.assert_array_equal(indices, expected)

if __name__ == "__main__":
    unittest.main()
