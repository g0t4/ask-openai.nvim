import json
from pathlib import Path
import subprocess
import unittest

import faiss
import numpy as np
from pygls.workspace import TextDocument
import rich

from indexer import IncrementalRAGIndexer
from lsp.chunker import RAGChunkerOptions
from lsp import model_qwen3_remote as model_wrapper2
from lsp.storage import load_chunks_by_file, load_file_stats_by_file

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
        return load_chunks_by_file(self.dot_rag_dir / "lua/chunks.json")

    def get_files(self):
        return load_file_stats_by_file(self.dot_rag_dir / "lua" / "files.json")

    def test_building_rag_index_from_scratch(self):

        # FYI! this duplicates some low level line range chunking tests but I want to keep it to include the end to end picture
        #   i.e. for computing chunk id which relies on path to file
        #   here I am testing end to end chunking outputs even if most logic is shared with low level tests, still valuable

        # * recreate index
        self.trash_path(self.dot_rag_dir)
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.indexer_src_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
        indexer.build_index(language_extension="lua")

        # * chunks
        chunks_by_file = self.get_chunks_by_file()
        # 41 lines currently, 5 overlap + 20 per chunk
        sample_lua_path = (self.indexer_src_dir / "sample.lua").absolute()
        self.assertEqual(len(chunks_by_file), 1)  # one file
        chunks = chunks_by_file[str(sample_lua_path)]
        self.assertEqual(len(chunks), 3)
        # rich.print(f'{sample_lua_path=}')
        for c in chunks:
            self.assertEqual(c.file, str(sample_lua_path))
            self.assertEqual(c.type, "lines")

        first_chunk = [c for c in chunks if c.start_line0 == 0][0]
        self.assertEqual(first_chunk.start_line0, 0)
        self.assertEqual(first_chunk.end_line0, 19)

        start = "\n\nlocal TestRunner = {}"
        self.assertEqual(first_chunk.text.startswith(start), True)
        end = "table.insert(self.results, {status = \"fail\", message = \"Test failed: expected \" .. tostring(test.expected) .. \", got \" .. tostring(result)})\n"
        self.assertEqual(first_chunk.text.endswith(end), True)
        # manually computed when running on my machine... so maybe warn if not same path
        # echo -n "/Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/tests/indexer_src/sample.lua:lines:0-19:b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b" | sha256sum | head -c16
        self.assertEqual(first_chunk.id, "e2d1d29ec4960e8f")
        # bitmaths "0xe2d1d29ec4960e8f & 0x7FFFFFFFFFFFFFFF"
        self.assertEqual(first_chunk.id_int, "7120704065194299023")

        second_chunk = [c for c in chunks if c.start_line0 == 15][0]
        self.assertEqual(second_chunk.start_line0, 15)
        self.assertEqual(second_chunk.end_line0, 34)

        third_chunk = [c for c in chunks if c.start_line0 == 30][0]
        self.assertEqual(third_chunk.start_line0, 30)
        self.assertEqual(third_chunk.end_line0, 40)

        # * files
        files = self.get_files()
        assert len(files) == 1
        file_meta = files[str(sample_lua_path)]

        # sha256sum /Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/tests/indexer_src/sample.lua | cut -d ' ' -f1
        self.assertEqual(file_meta.hash, "b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b")
        # PRN get rid of redundancy in path? already key
        self.assertEqual(file_meta.path, str(sample_lua_path))
        # how do I assert the timestamp is at least reasonable?
        self.assertTrue(file_meta.mtime > 1735711201)  # Jan 1 2025 00:00:00 UTC - before this code existed :)
        # cat tests/indexer_src/sample.lua | wc -c
        self.assertEqual(file_meta.size, 1_173)

        # * vectors
        # https://faiss.ai/cpp_api/struct/structfaiss_1_1IndexFlatIP.html
        index = self.get_vector_index()

        self.assertEqual(index.ntotal, 3)
        self.assertEqual(index.d, 1024)
        # rich.print(f'{index=}')
        # rich.print(f'{index.metric_type=}')
        # rich.print(f'{index.metric_arg=}')
        # rich.print(f'{index.is_trained=}')
        # for i in range(index.ntotal):
        #     rich.print(i)

    def test_search_index(self):
        # * setup same index as in the first test
        #   FYI updater tests will alter the index and break this test
        self.trash_path(self.dot_rag_dir)
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.indexer_src_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
        indexer.build_index(language_extension="lua")

        chunks_by_file = load_chunks_by_file(self.dot_rag_dir / "lua/chunks.json")
        self.assertEqual(len(chunks_by_file), 1)
        chunks = next(iter(chunks_by_file.values()))
        # I do not to replicate tests of building id/id_int and hard coding the values so...
        #   I am getting each chunk by its line range and I know which is which for the search results below
        #   that way if I ever change calculation for id_int I don't have to rewrite this test which is solely
        #   about search order and testing search works (get IDs back from faiss)
        chunk0 = [c for c in chunks if c.base0.start_line == 0][0]  # does not have hello in it and s/b last in search results
        chunk1 = [c for c in chunks if c.base0.start_line == 15][0]  # has hello
        chunk2 = [c for c in chunks if c.base0.start_line == 30][0]  # has hello
        #
        # # troubleshooting:
        # for i, c in enumerate(chunks):
        #     rich.print(f"\nchunk {i}\n  {c.id_int}\n\n{c.text}")

        q = model_wrapper2.encode_query(text="hello world", instruct="find code that uses + operator")
        self.assertEqual(q.shape, (1, 1024))

        index = self.get_vector_index()
        distances, indices = index.search(q, 3)
        # rich.print(f"{distances=}")
        # rich.print(f"{indices=}")

        expected = np.array([[int(chunk2.id_int), int(chunk1.id_int), int(chunk0.id_int)]])
        np.testing.assert_array_equal(indices, expected)

    def test_update_index_removed_file(self):
        self.trash_path(self.dot_rag_dir)
        # * recreate source directory with initial files
        self.trash_path(self.tmp_source_code_dir)
        self.tmp_source_code_dir.mkdir(exist_ok=True, parents=True)

        def copy_file(src, dest):
            (self.tmp_source_code_dir / dest).write_text((self.test_cases / src).read_text())

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
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
        copy_file("numbers.50.txt", "numbers.lua")  # 50 lines, 3 chunks (starts = 1-20, 16-35, 31-50)
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())  # BTW recreate so no shared state (i.e. if cache added)
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
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
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
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
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

    def test_reproduce_file_mod_time_updated_but_not_chunks_should_not_duplicate_vectors_in_index(self):
        self.trash_path(self.dot_rag_dir)
        # * recreate source directory with initial files
        self.trash_path(self.tmp_source_code_dir)
        self.tmp_source_code_dir.mkdir(exist_ok=True, parents=True)

        def copy_file(src, dest):
            (self.tmp_source_code_dir / dest).write_text((self.test_cases / src).read_text())

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        # copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
        indexer.build_index(language_extension="lua")

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        self.assertEqual(len(files), 1)
        #
        self.assertEqual(len(chunks_by_file), 1)  # 2 files
        first_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "numbers.lua")]
        # second_file_chunks = chunks_by_file[str(self.tmp_source_code_dir / "unchanged.lua")]
        self.assertEqual(len(first_file_chunks), 2)  # 2 chunks
        # self.assertEqual(len(second_file_chunks), 2)
        #
        self.assertEqual(index.ntotal, 2, "index.ntotal (num vectors) should be 1")

        copy_file("numbers.30.txt", "numbers.lua")
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
        indexer.build_index(language_extension="lua")

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        self.assertEqual(len(files), 1)
        #
        # this fails too but I am disabling it so I can run the 3rd indexing
        # self.assertEqual(index.ntotal, 2, "index.ntotal (num vectors) should be 1")

        # * 3rd rebuild - useful for compare new index 1 (new index), index 2 and index 3
        #  don't really need this to validate problem but I find it helpful to diff the logs
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
        indexer.build_index(language_extension="lua")

        self.assertEqual(index.ntotal, 2, "index.ntotal (num vectors) should be 1")

    def TODO_test__file_timestamp_changed__all_chunks_still_the_same__does_not_insert_chunk_into_updated_chunks(self):
        pass
        # ***! TODO FIX LOGIC TO DETECT CHANGED FILES/CHUNKS...
        #   if a chunk is the SAME it should be NOT marked updated!
        #   i.e. if file modified timestamp is updated but none of the contents are different!

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
        indexer = IncrementalRAGIndexer(self.dot_rag_dir, self.tmp_source_code_dir, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())
        indexer.build_index(language_extension="lua")

        from lsp import rag
        rag.load_model_and_indexes(self.dot_rag_dir, model_wrapper2)

        copy_file("numbers.50.txt", "numbers.lua")  # 50 lines, 3 chunks
        target_file_path = self.tmp_source_code_dir / "numbers.lua"
        fake_lsp_doc = TextDocument(
            uri=f"file://{target_file_path}",
            # language_id="lua",
            # version=2,
            source=target_file_path.read_text(encoding="utf-8"),
        )
        rag.update_file_from_pygls_doc(fake_lsp_doc, model_wrapper2, RAGChunkerOptions.OnlyLineRangeChunks())

        # * check counts
        datasets = rag.datasets
        ds = datasets.for_file(target_file_path)
        assert ds != None

        self.assertEqual(len(ds.chunks_by_file), 2)
        # * assert the list of chunks was updated for the file
        first_file_chunks = ds.chunks_by_file[str(self.tmp_source_code_dir / "numbers.lua")]
        second_file_chunks = ds.chunks_by_file[str(self.tmp_source_code_dir / "unchanged.lua")]
        self.assertEqual(len(first_file_chunks), 3)
        self.assertEqual(len(second_file_chunks), 2)
        hash_50nums = "02d36ee22aefffbb3eac4f90f703dd0be636851031144132b43af85384a2afcd"
        hash_30nums = "4becb4afc4bbb0706eb8df24e32b8924925961ef48a2ac0e4a95cd7da10e97a5"
        hash_unchanged = "aee2416e86cecb08a0b4e48a461d95a5d6d061e690145938a772ec62261653fc"
        for c in first_file_chunks:
            self.assertEqual(c.file_hash, hash_50nums)

        #
        # * assert vectors updated ...
        # TODO!!! CHECK ID values
        self.assertEqual(ds.index.ntotal, 5)
        #
        # * check global dict updated by faissid to new chunks
        self.assertEqual(len(datasets._chunks_by_faiss_id), 5)
        #
        # I hate the following... only alternative might be to compute and hardcode the ids?
        should_be_chunks = sorted(first_file_chunks.copy() + second_file_chunks.copy(), key=lambda x: x.id_int)
        actual_chunks_in_faiss_id_dict = sorted(list(datasets._chunks_by_faiss_id.copy().values()), key=lambda x: x.id_int)
        self.assertEqual(len(should_be_chunks), 5)
        self.assertEqual(len(actual_chunks_in_faiss_id_dict), 5)
        self.assertEqual(should_be_chunks, actual_chunks_in_faiss_id_dict)

        #
        # ? test interaction b/w indexer and update_file
        # ?   also update_file => update_file
        # ?   and update_file => indexer

    def PRN_tests_update_file_does_not_re_encode_unchanged_chunks(self):
        # PRN? is this worth the time?
        # would be nice not to re-encode them... that is the expensive part
        pass

    def PRN_test_timing_of_batch_vs_individual_chunk_encoding(self):
        # I suspect batching is a big boost in perf, but I need to understand more before I commit to designs one way or another
        pass

if __name__ == "__main__":
    # run with:
    #   python3 -m indexer_tests
    # TODO put back all tests when done with the one below
    unittest.main()
    # test = TestBuildIndex()
    # test.test_reproduce_file_mod_time_updated_but_not_chunks_should_not_duplicate_vectors_in_index()
