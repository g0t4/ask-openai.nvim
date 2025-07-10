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
        self.dot_rag_dir = Path(__file__).parent / "tests/.rag"
        self.dot_rag_dir.mkdir(exist_ok=True, parents=True)
        self.indexer_src_dir = Path(__file__).parent / "tests" / "indexer_src"
        self.tmp_source_code_dir = Path(__file__).parent / "tests" / "tmp_source_code"
        self.test_cases = Path(__file__).parent / "tests" / "test_cases"

    def trash_path(self, dir):
        if dir.exists():
            subprocess.run(["trash", dir])

    def get_vector_index(self):
        vectors_index_path = self.dot_rag_dir / "lua" / "vectors.index"
        index = faiss.read_index(str(vectors_index_path))
        return index

    def get_chunks_by_file(self):
        chunks_json_path = self.dot_rag_dir / "lua" / "chunks.json"
        return json.loads(chunks_json_path.read_text())

    def get_files(self):
        files_json_path = self.dot_rag_dir / "lua" / "files.json"
        return json.loads(files_json_path.read_text())

    def test_building_rag_index_from_scratch(self):

        # FYI! slow to recreate index, so do it once and comment this out to quickly run assertions
        # * recreate index
        self.trash_path(self.dot_rag_dir)
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.indexer_src_dir)
        indexer.build_index(language_extension="lua")

        # * chunks
        chunks_by_file = self.get_chunks_by_file()
        self.assertEqual(len(chunks_by_file), 1)  # only one test file
        # 41 lines currently, 5 overlap + 20 per chunk
        sample_lua_path = (self.indexer_src_dir / "sample.lua").absolute()
        self.assertEqual(chunks_by_file.keys(), {str(sample_lua_path)})
        chunks = chunks_by_file[str(sample_lua_path)]
        self.assertEqual(len(chunks), 3)
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
            # PRN verify vectors too?

    def test_slow__encode_and_search_index(self):
        from lsp.model import model_wrapper
        q = model_wrapper._encode_text("hello")
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

    def test_slow__update_index_removed_file(self):
        self.trash_path(self.dot_rag_dir)
        # * recreate source directory with initial files
        self.trash_path(self.tmp_source_code_dir)
        self.tmp_source_code_dir.mkdir(exist_ok=True, parents=True)

        def copy_file(src, dest):
            (self.tmp_source_code_dir / dest).write_text((self.test_cases / src).read_text())

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir)
        indexer.build_index(language_extension="lua")

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        self.assertEqual(len(files), 2)
        #
        self.assertEqual(len(chunks_by_file), 2)  # 2 files
        first_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "numbers.lua")]
        second_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "unchanged.lua")]
        self.assertEqual(len(first_file_chunks), 2)  # 2 chunks
        self.assertEqual(len(second_file_chunks), 2)
        #
        self.assertEqual(index.ntotal, 4)

        # * update a file and rebuild
        copy_file("numbers.50.txt", "numbers.lua")  # 50 lines, 4 chunks (starts = 1-20, 16-35, 31-50)
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir)  # BTW recreate so no shared state (i.e. if cache added)
        indexer.build_index(language_extension="lua")

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        self.assertEqual(len(chunks_by_file), 2)
        #
        first_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "numbers.lua")]
        second_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "unchanged.lua")]
        self.assertEqual(len(first_file_chunks), 3)
        self.assertEqual(len(second_file_chunks), 2)
        #
        self.assertEqual(len(files), 2)
        self.assertEqual(index.ntotal, 5)

        # * delete a file and rebuild
        (self.tmp_source_code_dir / "numbers.lua").unlink()
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir)
        indexer.build_index(language_extension="lua")
        #
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        self.assertEqual(len(chunks_by_file), 1)
        #
        only_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "unchanged.lua")]
        self.assertEqual(len(only_file_chunks), 2)
        #
        self.assertEqual(len(files), 1)
        self.assertEqual(index.ntotal, 2)

        # * add a file
        # FYI car.lua.txt was designed to catch issues with overlap (32 lines => 0 to 20, 15 to 35, but NOT 30 to 50 b/c only overlap exists so the next chunk has nothing unique in its non-overlapping segment) so maybe use a diff input file... if this causes issues here (move car.lua to a new test then)
        copy_file("car.lua.txt", "car.lua")
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir)
        indexer.build_index(language_extension="lua")
        #
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        self.assertEqual(len(chunks_by_file), 2)
        #
        first_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "unchanged.lua")]
        second_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "car.lua")]
        self.assertEqual(len(first_file_chunks), 2)
        self.assertEqual(len(second_file_chunks), 2)
        #
        self.assertEqual(len(files), 2)
        self.assertEqual(index.ntotal, 4)

    def test_update_file_from_language_server(self):
        self.trash_path(self.dot_rag_dir)
        # * recreate source directory with initial files
        self.trash_path(self.tmp_source_code_dir)
        self.tmp_source_code_dir.mkdir(exist_ok=True, parents=True)

        def copy_file(src, dest):
            (self.tmp_source_code_dir / dest).write_text((self.test_cases / src).read_text())

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir)
        indexer.build_index(language_extension="lua")
        #  TODO test interaction b/w indexer and update_file
        #    also update_file => update_file
        #    and update_file => indexer

        from lsp import rag
        rag.load_model_and_indexes(self.dot_rag_dir)
        #

        copy_file("numbers.50.txt", "numbers.lua")  # 50 lines, 4 chunks
        rag.update_one_file_from_disk(self.tmp_source_code_dir / "numbers.lua")

        # TODO
        # FYI I want to move much of the functionality into build.py module like indexer uses too...
        #  should not be LSP specific, needs to attach to RAGDataset really

if __name__ == "__main__":
    unittest.main()
