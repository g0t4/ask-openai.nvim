import os
from config.domains import find_files_by_semantic_domain
from logs import get_logger, logging_fwk_to_console, print_code

logger = get_logger(__name__)
# logging_fwk_to_console("INFO") # start info level to capture timing logs (add with logger.timer to below)

from pathlib import Path
import subprocess
import pytest

import faiss
import numpy as np
import rich

from indexer import IncrementalRAGIndexer
from chunks.chunker import RAGChunkerOptions
from inference.client.embedder import encode_query
from index.storage import ChunkType, load_all_datasets, load_chunks_by_file, load_file_stats_by_file
from config import RagConfig
from index.ignores import reset_cache_bewteen_tests
from index import workspace

# logging_fwk_to_console("WARN") # stop INFO logs after timing captured

my_dir = Path(__file__).parent
dot_rag_dir = my_dir / "tests/.rag"
dot_rag_dir.mkdir(exist_ok=True, parents=True)
index_test_cases_source_dir = my_dir / "index" / "test_cases"
tmp_code_dir = index_test_cases_source_dir / "tmp_source_code"
test_cases = my_dir / "chunks/test_cases"

def copy_file(original_file, destination_file):
    original_text = (test_cases / original_file).read_text()
    (tmp_code_dir / destination_file).write_text(original_text)

def trash_path(dir):
    if dir.exists():
        subprocess.run(["trash", dir])

def clean():
    reset_cache_bewteen_tests()  # fix for changing the cached root_path dir
    trash_path(dot_rag_dir)

    # recreate source directory with nothing at start of each test
    trash_path(tmp_code_dir)
    tmp_code_dir.mkdir(exist_ok=True, parents=True)

class TestBuildIndex:

    @classmethod
    def setup_class(cls):  # runs once before *all* tests in this class
        # TODO review workspace usage
        workspace.project.dot_rag_dir = dot_rag_dir
        workspace.project.folder = tmp_code_dir  # use this as default, override if different below

    def get_vector_index(self):
        vectors_index_path = dot_rag_dir / "lua" / "vectors.index"
        index = faiss.read_index(str(vectors_index_path))
        return index

    def get_chunks_by_file(self):
        return load_chunks_by_file(dot_rag_dir / "lua/chunks.json")

    def get_files(self):
        return load_file_stats_by_file(dot_rag_dir / "lua" / "files.json")

    async def build_lua_index(self, path: Path):
        files_by_domain = find_files_by_semantic_domain(path)
        files = files_by_domain.get("lua", set())
        indexer = IncrementalRAGIndexer(workspace.project.dot_rag_dir, path, RAGChunkerOptions.OnlyLineRangeChunks(), None, RagConfig.default())
        await indexer.build_index(domain="lua", current_files=files)

    @pytest.mark.asyncio
    async def test_building_rag_index_from_scratch(self):
        # FYI! this duplicates some low level line range chunking tests but I want to keep it to include the end to end picture
        #   i.e. for computing chunk id which relies on path to file
        #   here I am testing end to end chunking outputs even if most logic is shared with low level tests, still valuable
        clean()
        workspace.project.folder = index_test_cases_source_dir

        await self.build_lua_index(index_test_cases_source_dir)
        # * chunks
        chunks_by_file = self.get_chunks_by_file()
        # 41 lines currently, 5 overlap + 20 per chunk
        sample_lua_path = (index_test_cases_source_dir / "sample.lua").absolute()
        assert len(chunks_by_file) == 1  # one file
        chunks = chunks_by_file[str(sample_lua_path)]
        assert len(chunks) == 3
        # rich.print(f'{sample_lua_path=}')
        for c in chunks:
            assert c.file == str(sample_lua_path)
            assert c.type == ChunkType.LINES

        first_chunk = [c for c in chunks if c.start_line0 == 0][0]
        assert first_chunk.start_line0 == 0
        assert first_chunk.end_line0 == 19

        start = "\n\nlocal TestRunner = {}"
        assert first_chunk.text.startswith(start) == True
        end = "table.insert(self.results, {status = \"fail\", message = \"Test failed: expected \" .. tostring(test.expected) .. \", got \" .. tostring(result)})\n"
        assert first_chunk.text.endswith(end) == True

        home_dir: str = os.path.expanduser('~')
        if home_dir != "/Users/wesdemos":
            raise RuntimeError(f"Shit, your home dir is {home_dir}. This test only runs on /Users/wesdemos.")

        # manually computed when running on my machine... so maybe warn if not same path
        # echo -n "/Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/index/test_cases/sample.lua:lines:0-19:b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b" | sha256sum | head -c16
        assert first_chunk.id == "279dc6999a6fabdf"
        # bitmaths "0x279dc6999a6fabdf & 0x7FFFFFFFFFFFFFFF"
        assert first_chunk.id_int == "2854656101846068191"

        second_chunk = [c for c in chunks if c.start_line0 == 15][0]
        assert second_chunk.start_line0 == 15
        assert second_chunk.end_line0 == 34

        third_chunk = [c for c in chunks if c.start_line0 == 30][0]
        assert third_chunk.start_line0 == 30
        assert third_chunk.end_line0 == 40

        # * files
        files = self.get_files()
        assert len(files) == 1
        file_meta = files[str(sample_lua_path)]

        # sha256sum /Users/wesdemos/repos/github/g0t4/ask-openai.nvim/lua/ask-openai/rag/tests/indexer_src/sample.lua | cut -d ' ' -f1
        assert file_meta.hash == "b9686ac7736365ba5870d7967678fbd80b9dc527c18d4642b2ef1a4056ec495b"
        # PRN get rid of redundancy in path? already key
        assert file_meta.path == str(sample_lua_path)
        # how do I assert the timestamp is at least reasonable?
        assert file_meta.mtime > 1735711201  # Jan 1 2025 00:00:00 UTC - before this code existed :)
        # cat tests/indexer_src/sample.lua | wc -c
        assert file_meta.size == 1_173

        # * vectors
        # https://faiss.ai/cpp_api/struct/structfaiss_1_1IndexFlatIP.html
        index = self.get_vector_index()

        assert index.ntotal == 3
        assert index.d == 1024
        # rich.print(f'{index=}')
        # rich.print(f'{index.metric_type=}')
        # rich.print(f'{index.metric_arg=}')
        # rich.print(f'{index.is_trained=}')
        # for i in range(index.ntotal):
        #     rich.print(i)

    @pytest.mark.asyncio
    async def test_search_index_to_trigger_OpenMP_error(self):
        clean()
        workspace.project.folder = index_test_cases_source_dir

        # * setup same index as in the first test
        #   FYI updater tests will alter the index and break this test
        await self.build_lua_index(index_test_cases_source_dir)

        chunks_by_file = load_chunks_by_file(dot_rag_dir / "lua/chunks.json")
        assert len(chunks_by_file) == 1
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
        #     print_code(f"\nchunk {i}\n  {c.id_int}\n\n{c.text}")

        # ***! TODO USE THIS TO FIX OpenMP issue
        #
        # run this test ignoring OpenMP error (shows test works fine otherwise):
        #    KMP_DUPLICATE_LIB_OK=TRUE ptw indexer_tests.py -- --verbose --capture=no indexer_tests.py::TestBuildIndex::test_search_index_to_trigger_OpenMP_error
        #    * drop the KMP_DUPLICATE_LIB_OK to get the exception again
        #    make sure to include --capture=no else pytest swallows Error text
        #
        #    indexer_tests.py::TestBuildIndex::test_search_index OMP: Error #15: Initializing libomp.dylib, but found libomp.dylib already initialized.
        #    OMP: Hint This means that multiple copies of the OpenMP runtime have been linked into the program. That is dangerous, since it can degrade performance or cause incorrect results. The best thing to do is to ensure that only a single OpenMP runtime is linked into the process, e.g. by avoiding static linking of the OpenMP runtime in any library. As an unsafe, unsupported, undocumented workaround you can set the environment variable KMP_DUPLICATE_LIB_OK=TRUE to allow the program to continue to execute, but that may cause crashes or silently produce incorrect results. For more information, please see http://openmp.llvm.org/
        #    Fatal Python error: Aborted       #
        #
        # by the way, the code that triggers this is the index.search below
        #   my guess is smth to do with load order of torch/numpy/faiss
        #   though, everything works fine until I try to search
        #   FYI I also tried using semantic_grep which also uses faiss.search here instead and got same error
        #
        # BTW I do not need this test, I already have search covered in other tests
        #   this was just the very first search I tried with faiss and so it lingers
        #   that said, good test case now! and then maybe keep this and rename it!

        q = await encode_query(query="hello world", instruct="find code that uses + operator")
        assert q.shape == (1, 1024)

        index = self.get_vector_index()
        # FYI this causes OMP OpenMP error:
        distances, indices = index.search(q, 3)
        # rich.print(f"{distances=}")
        # rich.print(f"{indices=}")

        expected = np.array([[int(chunk2.id_int), int(chunk1.id_int), int(chunk0.id_int)]])
        np.testing.assert_array_equal(indices, expected)

    @pytest.mark.asyncio
    async def test_update_index_removed_file(self):
        clean()

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        await self.build_lua_index(tmp_code_dir)

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        assert len(files) == 2
        #
        assert len(chunks_by_file) == 2  # 2 files
        first_file_chunks = chunks_by_file[str(tmp_code_dir / "numbers.lua")]
        second_file_chunks = chunks_by_file[str(tmp_code_dir / "unchanged.lua")]
        assert len(first_file_chunks) == 2  # 2 chunks
        assert len(second_file_chunks) == 2
        #
        assert index.ntotal == 4

        # * update a file and rebuild
        copy_file("numbers.50.txt", "numbers.lua")  # 50 lines, 3 chunks (starts = 1-20, 16-35, 31-50)
        await self.build_lua_index(tmp_code_dir)

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        assert len(chunks_by_file) == 2
        #
        first_file_chunks = chunks_by_file[str(tmp_code_dir / "numbers.lua")]
        second_file_chunks = chunks_by_file[str(tmp_code_dir / "unchanged.lua")]
        assert len(first_file_chunks) == 3
        assert len(second_file_chunks) == 2
        assert len(files) == 2
        assert index.ntotal == 5

        # * delete a file and rebuild
        (tmp_code_dir / "numbers.lua").unlink()
        await self.build_lua_index(tmp_code_dir)
        #
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        assert len(chunks_by_file) == 1
        #
        only_file_chunks = chunks_by_file[str(tmp_code_dir / "unchanged.lua")]
        assert len(only_file_chunks) == 2
        assert len(files) == 1
        assert index.ntotal == 2

        # * add a file
        # FYI car.lua.txt was designed to catch issues with overlap (32 lines => 0 to 20, 15 to 35, but NOT 30 to 50 b/c only overlap exists so the next chunk has nothing unique in its non-overlapping segment) so maybe use a diff input file... if this causes issues here (move car.lua to a new test then)
        copy_file("car.lua.txt", "car.lua")
        await self.build_lua_index(tmp_code_dir)
        #
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        assert len(chunks_by_file) == 2
        #
        first_file_chunks = chunks_by_file[str(tmp_code_dir / "unchanged.lua")]
        second_file_chunks = chunks_by_file[str(tmp_code_dir / "car.lua")]
        assert len(first_file_chunks) == 2
        assert len(second_file_chunks) == 2
        #
        assert len(files) == 2
        assert index.ntotal == 4

    @pytest.mark.asyncio
    async def test_reproduce_file_mod_time_updated_but_not_chunks_should_not_duplicate_vectors_in_index(self):
        clean()

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        # copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        await self.build_lua_index(tmp_code_dir)

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        assert len(files) == 1
        #
        assert len(chunks_by_file) == 1  # 2 files
        first_file_chunks = chunks_by_file[str(tmp_code_dir / "numbers.lua")]
        # second_file_chunks = chunks_by_file[str(tmp_source_code_dir / "unchanged.lua")]
        assert len(first_file_chunks) == 2  # 2 chunks
        # assert len(second_file_chunks) == 2
        #
        assert index.ntotal == 2, "index.ntotal (num vectors) should be 1"

        copy_file("numbers.30.txt", "numbers.lua")
        await self.build_lua_index(tmp_code_dir)

        # * check counts
        chunks_by_file = self.get_chunks_by_file()
        files = self.get_files()
        index = self.get_vector_index()
        #
        assert len(files) == 1
        #
        # this fails too but I am disabling it so I can run the 3rd indexing
        # assert index.ntotal == 2, "index.ntotal (num vectors) should be 1"

        # * 3rd rebuild - useful for compare new index 1 (new index), index 2 and index 3
        #  don't really need this to validate problem but I find it helpful to diff the logs
        await self.build_lua_index(tmp_code_dir)

        assert index.ntotal == 2, "index.ntotal (num vectors) should be 1"

    # @pytest.mark.asyncio
    async def TODO_test__file_timestamp_changed__all_chunks_still_the_same__does_not_insert_chunk_into_updated_chunks(self):
        pass
        # ***! TODO FIX LOGIC TO DETECT CHANGED FILES/CHUNKS...
        #   if a chunk is the SAME it should be NOT marked updated!
        #   i.e. if file modified timestamp is updated but none of the contents are different!

    @pytest.mark.asyncio
    async def test_update_file_from_language_server(self):
        clean()

        copy_file("numbers.30.txt", "numbers.lua")  # 30 lines, 2 chunks
        copy_file("unchanged.lua.txt", "unchanged.lua")  # 31 lines, 2 chunks

        # * build initial index
        await self.build_lua_index(tmp_code_dir)

        datasets = load_all_datasets(dot_rag_dir)

        copy_file("numbers.50.txt", "numbers.lua")  # 50 lines, 3 chunks
        target_file_path = tmp_code_dir / "numbers.lua"

        from pygls.workspace import TextDocument  # 130ms so leave it here
        fake_lsp_doc = TextDocument(
            uri=f"file://{target_file_path}",
            # language_id="lua",
            # version=2,
            source=target_file_path.read_text(encoding="utf-8"),
        )

        from language_server.commands.update_file import update_file_from_pygls_doc
        await update_file_from_pygls_doc(fake_lsp_doc, RAGChunkerOptions.OnlyLineRangeChunks(), datasets)

        # * check counts
        ds = datasets.for_file(target_file_path)
        assert ds != None

        assert len(ds.chunks_by_file) == 2
        # * assert the list of chunks was updated for the file
        first_file_chunks = ds.chunks_by_file[str(tmp_code_dir / "numbers.lua")]
        second_file_chunks = ds.chunks_by_file[str(tmp_code_dir / "unchanged.lua")]
        assert len(first_file_chunks) == 3
        assert len(second_file_chunks) == 2
        hash_50nums = "02d36ee22aefffbb3eac4f90f703dd0be636851031144132b43af85384a2afcd"
        hash_30nums = "4becb4afc4bbb0706eb8df24e32b8924925961ef48a2ac0e4a95cd7da10e97a5"
        hash_unchanged = "aee2416e86cecb08a0b4e48a461d95a5d6d061e690145938a772ec62261653fc"
        for c in first_file_chunks:
            assert c.file_hash == hash_50nums

        #
        # * assert vectors updated ...
        # TODO!!! CHECK ID values
        assert ds.index.ntotal == 5
        #
        # * check global dict updated by faissid to new chunks
        assert len(datasets._chunks_by_faiss_id) == 5
        #
        # I hate the following... only alternative might be to compute and hardcode the ids?
        should_be_chunks = sorted(first_file_chunks.copy() + second_file_chunks.copy(), key=lambda x: x.id_int)
        actual_chunks_in_faiss_id_dict = sorted(list(datasets._chunks_by_faiss_id.copy().values()), key=lambda x: x.id_int)
        assert len(should_be_chunks) == 5
        assert len(actual_chunks_in_faiss_id_dict) == 5
        assert should_be_chunks == actual_chunks_in_faiss_id_dict

        #
        # ? test interaction b/w indexer and update_file
        # ?   also update_file => update_file
        # ?   and update_file => indexer

    # @pytest.mark.asyncio
    async def PRN_tests_update_file_does_not_re_encode_unchanged_chunks():
        # PRN? is this worth the time?
        # would be nice not to re-encode them... that is the expensive part
        pass

    # @pytest.mark.asyncio
    async def PRN_test_timing_of_batch_vs_individual_chunk_encoding():
        # I suspect batching is a big boost in perf, but I need to understand more before I commit to designs one way or another
        pass
