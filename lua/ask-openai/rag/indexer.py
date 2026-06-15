import aiofiles
import asyncio
from lsp.logs import disable_printtmp, get_logger, disable_printtmp
from lsp.inference.client.embedder import get_shape, encode_passages, signal_hotpath_done_in_background

logger = get_logger(__name__)

import argparse
import logging
import subprocess
import sys
import yaml
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Set

import faiss
import numpy as np

from pydants import write_json

from lsp.storage import Chunk, FileStat, load_prior_data
from lsp.chunks.chunker import RAGChunkerOptions, build_chunks_from_file, get_file_stat
from lsp.config import Config, load_config
from lsp.ignores import is_ignored_allchecks
from lsp.domains import (
    EXTENSION_TO_FILETYPE,
    resolve_retrieval_domain,
)
from lsp import fs

# constants for subprocess.run for readability
IGNORE_FAILURE = False
STOP_ON_FAILURE = True


@dataclass
class FilesDiff:
    # FYI type mismatch IS FINE with type hints... LEAVE IT!
    changed: Set[Path]
    deleted: Set[str]
    not_changed: Set[str]


@dataclass
class ProgramArgs:
    verbose: bool
    info: bool
    in_githook: bool
    rebuild: bool
    level: int
    only_filetype: str | None = None


def trash_dir(directory):
    directory = Path(directory)
    if not directory.exists():
        return
    subprocess.run(["trash", directory], check=IGNORE_FAILURE)


class IncrementalRAGIndexer:

    def __init__(
        self,
        dot_rag_dir: Path,
        source_code_dir: Path,
        options: RAGChunkerOptions,
        program_args: ProgramArgs,
        config: Config,
    ):
        self.options = options
        self.dot_rag_dir = Path(dot_rag_dir)
        self.source_code_dir = Path(source_code_dir)
        self.program_args = program_args
        self.config = config
        # TODO pass root_path instead of using fs (IF I even need it  here anymore... was it just here for ignores?)

    async def main(self):
        if not self.config.enabled:
            logger.warning(f"RAG indexing disabled in {self.source_code_dir / '.rag.yaml'}, ")
            return

        included_filetypes = self.config.included_filetypes
        if self.program_args and self.program_args.only_filetype:
            included_filetypes = {self.program_args.only_filetype}
            logger.info(f"Indexing only filetype: {included_filetypes}")

        def find_all_files():
            fd_command = [
                "fd",
                "--type", "file", \
                "--absolute-path",
                ".",
                str(self.source_code_dir),
            ]
            out = subprocess.check_output(fd_command, text=True)

            files_by_type = {}
            for file_path in out.splitlines():
                filetype = resolve_retrieval_domain(file_path)
                if filetype:
                    files_by_type.setdefault(filetype, set()).add(file_path)
                else:
                    pass
                    # TODO warn, or?

            return files_by_type

        files_by_type = find_all_files()

        for filetype in included_filetypes:
            files = files_by_type.get(filetype, set())
            await self.build_index(filetype, files)

        self.flag_unindexed_filetypes_with_file_counts(included_filetypes)
        self.trash_vestigial_filetype_indexes(included_filetypes)
        await signal_hotpath_done_in_background()

    def trash_vestigial_filetype_indexes(self, allowed_filetypes: set[str]):
        rag_dir_dirs = [p for p in self.dot_rag_dir.iterdir() if p.is_dir()]
        indexed_filetypes = {d.name for d in rag_dir_dirs}
        vestigial_filetypes = indexed_filetypes - allowed_filetypes

        if not any(vestigial_filetypes):
            return

        logger.warning(f'FYI found {vestigial_filetypes=}, removing...')

        for name in vestigial_filetypes:
            filetype_dir = self.dot_rag_dir / name
            logger.warning(f"Removing vestigial rag dir: {filetype_dir}")
            trash_dir(filetype_dir)

    def flag_unindexed_filetypes_with_file_counts(self, expected_filetypes: set[str]):
        """Warn about filetypes present in the repo but not being indexed."""

        cmd = ["fish", "-c", f"fd . {self.source_code_dir} --exclude='\\.ctags\\.d' --exclude='\\.rag' --exec basename"]
        logger.debug("warn cmd", cmd)
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            text=True,
            check=STOP_ON_FAILURE,
        )
        basenames = result.stdout.strip().splitlines()

        ignore_files = {"ctags", "ctags.d"}

        # Resolve each basename to its filetype
        filetypes: list[str] = []
        for basename in basenames:
            if not basename or basename in ignore_files or "." not in basename:
                continue
            ext = basename.rsplit(".", 1)[-1]
            filetype = EXTENSION_TO_FILETYPE.get(ext, ext)
            filetypes.append(filetype)

        import itertools
        unindexed_filetypes = [(ft, len(list(group))) \
            for ft, group in itertools.groupby(sorted(filetypes)) \
            if ft not in expected_filetypes
        ]

        noteworthy_filetypes = [ \
            f"{ft}={count}" \
            for ft, count in unindexed_filetypes \
            if count > 1
        ]

        if noteworthy_filetypes:
            logger.debug(f"Found unindexed filetypes: {' '.join(noteworthy_filetypes)}")

    def get_files_diff(self, current_files_path_strs: set[str], prior_files_stat_by_path: dict[str, FileStat]) -> FilesDiff:
        """Split files into: changed (added/updated), unchanged, deleted"""

        # * ignored files
        ignored_path_strs: Set[str] = set()
        for path_str in current_files_path_strs:
            if is_ignored_allchecks(path_str, self.config, self.source_code_dir):
                ignored_path_strs.add(path_str)
        if len(ignored_path_strs) > 0:
            logger.info(f"Ignoring files ({len(ignored_path_strs)}):\n    {'\n    '.join(ignored_path_strs)}")
        current_files_path_strs -= ignored_path_strs

        # * added, modified (aka changed)
        changed_paths: Set[Path] = set()
        for file_path_str in current_files_path_strs:
            file_path = Path(file_path_str)
            is_new_file = file_path_str not in prior_files_stat_by_path
            if is_new_file:
                changed_paths.add(file_path)
                logger.debug(f"[green]New file: {file_path}")
            else:
                current_mod_time = file_path.stat().st_mtime
                prior_mod_time = prior_files_stat_by_path[file_path_str].mtime
                if current_mod_time > prior_mod_time:
                    changed_paths.add(file_path)
                    logger.debug(f"[blue]Modified file: {file_path}")

        prior_path_strs: Set[str] = set(prior_files_stat_by_path.keys())

        # * deleted
        deleted_path_strs = prior_path_strs - current_files_path_strs
        for deleted_file in deleted_path_strs:
            logger.debug(f"[red]Deleted file: {deleted_file}")

        # * not changed
        changed_path_strs = set(str(f) for f in changed_paths)
        not_changed_path_strs = prior_path_strs - changed_path_strs - deleted_path_strs

        return FilesDiff(changed_paths, deleted_path_strs, not_changed_path_strs)

    async def update_faiss_index_incrementally(
        self,
        index: Optional[faiss.Index],
        not_changed_chunks_by_file: dict[str, list[Chunk]],
        updated_chunks_by_file: dict[str, list[Chunk]],
    ) -> faiss.Index:
        """Update FAISS index incrementally using IndexIDMap"""

        # Create base index if it doesn't exist
        if index is None:
            shape = await get_shape()
            # 768 for "intfloat/e5-base-v2"
            # 1024 for Qwen3
            base_index = faiss.IndexFlatIP(shape)
            index = faiss.IndexIDMap(base_index)
            # FYI if someone deletes the vectors file... this won't recreate it if stat still exists...

        new_chunks: list[Chunk] = []
        new_faiss_ids: list[int] = []
        for file_chunks in updated_chunks_by_file.values():
            for chunk in file_chunks:
                new_chunks.append(chunk)
                new_faiss_ids.append(chunk.faiss_id)

        # FYI FIX THE updated check logic... don't try to work around it here
        #  fix it so a chunk that is VERBATIM same content is NOT marked updated just b/c another part of the file is... OR just b/c timestamp on file changes!
        keep_ids = []  # why was I keeping things that are marked updated?!
        logger.pp_debug("keep_ids - before", keep_ids)
        for _, file_chunks in not_changed_chunks_by_file.items():
            for chunk in file_chunks:
                keep_ids.append(chunk.faiss_id)
        logger.pp_debug("keep_ids - after", keep_ids)

        # BUG: currently updated files, the chunks that don't change (or entire thing if just msec updated)...
        #   these chunks IDs are put into keep_ids AND chunks go into new_chunks
        #   and so we insert them again (double them up)
        keep_selector = faiss.IDSelectorArray(np.array(keep_ids, dtype="int64"))
        not_keep_selector = faiss.IDSelectorNot(keep_selector)
        index.remove_ids(not_keep_selector)

        if new_chunks:
            logger.pp_debug("new_faiss_ids", new_faiss_ids)

            with logger.timer("Encode new vectors"):
                passages = [chunk.text for chunk in new_chunks]
                vecs_np = await encode_passages(passages)

            faiss_ids_np = np.array(new_faiss_ids, dtype="int64")

            index.add_with_ids(vecs_np, faiss_ids_np)

        return index

    async def build_index(self, filetype: str = "lua", current_files: set[str] = set()):
        """Build or update the RAG index incrementally for a given filetype."""

        prior_files = load_prior_data(self.dot_rag_dir, filetype)

        files_diff = self.get_files_diff(current_files, prior_files.stat_by_path)

        # TODO add test to assert delete last file is fine and wipes the data set

        logger.pp_debug("files_diff", files_diff)

        if not files_diff.changed and not files_diff.deleted:
            logger.debug("[green]No changes detected, index is up to date!")
            return

        all_stat_by_path = {path_str: prior_files.stat_by_path[path_str] for path_str in files_diff.not_changed}
        not_changed_chunks_by_file = {path_str: prior_files.chunks_by_file[path_str] for path_str in files_diff.not_changed}
        logger.info(f'{len(files_diff.changed)} changed, {len(files_diff.deleted)} deleted')

        updated_chunks_by_file: dict[str, list[Chunk]] = {}
        for file_path in files_diff.changed:
            file_path_str = str(file_path)

            stat = get_file_stat(file_path)
            all_stat_by_path[file_path_str] = stat

            # Create new chunks for this file
            chunks = build_chunks_from_file(file_path, stat.hash, self.options)
            updated_chunks_by_file[file_path_str] = chunks

        logger.pp_debug("Deleted chunks", files_diff.deleted)
        logger.pp_debug("Updated chunks", updated_chunks_by_file)
        logger.pp_debug("NOT changed chunks", not_changed_chunks_by_file)

        # * Incrementally update the FAISS index
        if files_diff.changed or files_diff.deleted:
            index = await self.update_faiss_index_incrementally(
                prior_files.index,
                not_changed_chunks_by_file,
                updated_chunks_by_file,
            )
        else:
            index = prior_files.index

        if index is None:
            return

        # Save everything under the filetype key
        index_dir = self.dot_rag_dir / filetype
        index_dir.mkdir(exist_ok=True, parents=True)

        faiss.write_index(index, str(index_dir / "vectors.index"))

        logger.pp_debug("ids: ", prior_files.index_view.ids)

        with logger.timer("Save chunks"):
            all_chunks_by_file = not_changed_chunks_by_file.copy()
            all_chunks_by_file.update(updated_chunks_by_file)
            # logger.pp_debug("all_chunks_by_file", all_chunks_by_file)
            # logger.pp_debug("all_stat_by_path", all_stat_by_path)

        with logger.timer("Save chunks"):
            write_json(all_chunks_by_file, index_dir / "chunks.json")

        with logger.timer("Save file stats"):
            write_json(all_stat_by_path, index_dir / "files.json")

        logger.debug(f"[green]Index updated successfully!")
        if files_diff.changed:
            logger.debug(f"[green]Processed {len(files_diff.changed)} changed files")
        if files_diff.deleted:
            logger.debug(f"[green]Removed {len(files_diff.deleted)} deleted files")


async def main():
    from lsp.logs import logging_fwk_to_console

    def parse_program_args() -> ProgramArgs:
        parser = argparse.ArgumentParser()
        parser.add_argument("--verbose", "--debug", action="store_true", help="Enable verbose logging")
        parser.add_argument("--info", action="store_true", help="Enable info logging")
        parser.add_argument("--rebuild", action="store_true", help="Rebuild index")
        parser.add_argument("--githook", action="store_true", help="Run in git hook mode")
        parser.add_argument("--only-filetype", type=str, help="Only process files with the specified filetype")

        args = parser.parse_args()

        program_args = ProgramArgs(
            verbose=args.verbose,
            info=args.info,
            in_githook=args.githook,
            rebuild=args.rebuild,
            level=logging.WARNING,
            only_filetype=args.only_filetype,
        )
        if args.githook:
            level = logging.INFO
        else:
            program_args.level = logging.DEBUG if args.verbose else (logging.INFO if args.info else logging.WARNING)

        return program_args

    disable_printtmp()  # output intended for testing only

    args = parse_program_args()
    # print("args", args)

    logging_fwk_to_console(args.level)

    with logger.timer("Total indexing time"):
        # PRN make this work in CWD first, fallback to repo root? like lua code? only when I only want a subset of a repo or non-repos
        repo_root_dir = fs.get_cwd_repo_root()
        if not repo_root_dir:
            logger.error("[red]No Git repository found in current working directory, cannot build RAG index.")
            sys.exit(1)
        dot_rag_dir = repo_root_dir / ".rag"
        source_code_dir = Path(".").resolve()  # TODO make this repo_root_dir always? has been nice to test a subset of files by cd to nested dir
        # FYI added .resolve() recently, leave a note just in case that causes issues so you remember (2026-01-26... remove this in a few weeks max)
        logger.debug(f"[bold]RAG directory: {dot_rag_dir}")
        if args.rebuild:
            trash_dir(dot_rag_dir)

        options = RAGChunkerOptions.ProductionOptions()
        config = await fs.load_rag_config(source_code_dir)
        indexer = IncrementalRAGIndexer(dot_rag_dir, source_code_dir, options, args, config)

        # * STOPGAP: fs integration is just for ignores to work for now
        #   FYI! minimize using fs module beyond ignores
        #   I'd prefer to rip out the fs module's global state and instead
        #   make a state obj like IncrementalRAGIndexer's ctor has!
        #     modify ignores to take this new state object (like it takes config and doesn't use config from fs.config!)
        #   and push that over into pygls code that originally created the fs module
        #   TODO rip this crap out long term
        fs.root_path = source_code_dir
        fs.dot_rag_dir = dot_rag_dir

        await indexer.main()


if __name__ == "__main__":
    asyncio.run(main())
