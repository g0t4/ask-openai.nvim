import logging
import time
from dataclasses import dataclass
from pathlib import Path
from rich.table import Table
from rich.console import Console

from config.domains import find_files_by_semantic_domain
from index.storage import Datasets, FileStat
from index.workspace import RagConfig, get_relative_path_to
from chunks.chunker import get_file_stat
from index.ignores import _is_gitignored

logger = logging.getLogger(__name__)


def format_age(age_seconds: float) -> str:
    """Format age in days with color coding."""
    days = 24 * 60 * 60
    if age_seconds > 7 * days:
        return f"[red]{age_seconds / days:.1f}d[/]"
    if age_seconds > 2 * days:
        return f"[yellow]{age_seconds / days:.1f}d[/]"
    return f"[green]{age_seconds / days:.1f}d[/]"


@dataclass(frozen=True)
class AddedFile:
    """A file present in the repo but not yet indexed."""
    path: str
    display_path: Path
    current_stat: FileStat


@dataclass(frozen=True)
class StaleFile:
    """An indexed file whose stored hash differs from current hash."""
    path: str
    display_path: Path
    stored_stat: FileStat
    current_stat: FileStat


@dataclass(frozen=True)
class MtimeOnlyFile:
    """An indexed file with only mtime difference (hash matches)."""
    path: str
    display_path: Path
    stored_stat: FileStat
    current_stat: FileStat


@dataclass(frozen=True)
class DeletedFile:
    """An indexed file that no longer exists on disk."""
    path: str
    display_path: Path
    stored_stat: FileStat


def warn_about_file_differences(datasets: Datasets, config: RagConfig, root_dir: Path) -> None:
    """Warn about files that differ between the index and the filesystem.

    Compares indexed files against all files found via semantic domain matching.
    Reports: added (unindexed), stale (hash mismatch), mtime-only, and deleted files.
    """

    HIDE_NOT_IN_CONFIG = "NOT_IN_CONFIG"
    HIDE_IGNORED = "IGNORED"
    verbose = False
    # * files on disk *
    files_by_domain = find_files_by_semantic_domain(root_dir)
    all_disk_stats: dict[str, FileStat] = {}
    hide_reason_by_file_path: dict[str, str] = {}
    for domain, files in files_by_domain.items():
        for path in files:
            if domain not in config.allowed_semantic_domains:
                # FYI I could bulk mark entire domain as hidden instead of individual files
                #    also might wanna show hidden by domain? (could call into same display logic with hidden reason (None/HIDE_IGNORED/HIDE_NOT_IN_CONFIG/etc)
                hide_reason_by_file_path[path] = HIDE_NOT_IN_CONFIG
                if not verbose:
                    continue
            # TODO revisit _is_file_ignored_allchecks instead of only l_is_gitignored here?
            #   ? reuse same checks across all consumers?
            #   perhaps return hidden reason there instead of here too?
            #   PRN split out lookup semantic domain from check config if domain is allowed? => that way I can lookup domain in different ways but keep rest of logic the same?
            if _is_gitignored(path, root_dir, config):
                hide_reason_by_file_path[path] = HIDE_IGNORED
                if not verbose:
                    continue

            all_disk_stats[path] = get_file_stat(path)

    # * files in index *
    all_index_stats: dict[str, FileStat] = {}
    for dataset in datasets.all_datasets.values():
        all_index_stats.update(dataset.stat_by_path)

    added_files: list[AddedFile] = []
    content_differs: list[StaleFile] = []
    only_mtime_differs_files: list[MtimeOnlyFile] = []
    deleted_files: list[DeletedFile] = []

    # * indexed files comparison
    for path, index_stat in all_index_stats.items():
        display_path = get_relative_path_to(path, override_root_path=root_dir)

        # * deleted files
        if path not in all_disk_stats:
            deleted_files.append(DeletedFile(path, display_path, index_stat))
            continue

        disk_stat = all_disk_stats[path]

        # * content differs
        hash_differs = disk_stat.hash != index_stat.hash
        if hash_differs:
            content_differs.append(StaleFile(path, display_path, index_stat, disk_stat))
            continue

        # * only mtime differs
        mtime_differs = abs(index_stat.mtime - disk_stat.mtime) > 0
        if mtime_differs:
            only_mtime_differs_files.append(MtimeOnlyFile(path, display_path, index_stat, disk_stat))

    # * added files
    for path, disk_stat in all_disk_stats.items():
        if path not in all_index_stats:
            display_path = get_relative_path_to(path, override_root_path=root_dir)
            added_files.append(AddedFile(path, display_path, disk_stat))

    if not (added_files or content_differs or only_mtime_differs_files or deleted_files):
        logger.info("[bold green]All files are in sync — no differences found![/]")
        return

    console = Console()
    console.print()
    console.print("[bold white]FILE DIFFERENCES:[/]")
    console.print("[italic]  run [bold]rag_indexer[/bold] to update the index...[/]\n")

    if added_files:
        added_files.sort(key=lambda x: x.current_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="age", header_style="not bold white italic")
        table.add_column(justify="left", header="added (not yet indexed)")
        table.add_column(justify="left", header="hidden")
        for added_file in added_files:
            file_age = time.time() - added_file.current_stat.mtime
            age_str = format_age(file_age)
            hidden = hide_reason_by_file_path.get(added_file.path)
            table.add_row(age_str, str(added_file.display_path), hidden)
        console.print(table)

    if content_differs:
        content_differs.sort(key=lambda x: x.stored_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="path")
        table.add_column(justify="left", header="size")
        table.add_column(justify="left", header="hash")
        table.add_column(justify="left", header="hidden")
        for stale_file in content_differs:
            last_indexed = format_age(time.time() - stale_file.stored_stat.mtime)

            if stale_file.current_stat.size != stale_file.stored_stat.size:
                delta = stale_file.current_stat.size - stale_file.stored_stat.size
                sign = "+" if delta > 0 else "-"
                size_str = f"{sign}{abs(delta)}"
            else:
                size_str = ""

            hidden = hide_reason_by_file_path.get(stale_file.path)
            hash_str = f"{stale_file.stored_stat.hash[:8]}→{stale_file.current_stat.hash[:8]}"
            table.add_row(last_indexed, str(stale_file.display_path), size_str, hash_str, hidden)
        console.print(table)

    if only_mtime_differs_files:
        only_mtime_differs_files.sort(key=lambda x: x.stored_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="only mtime differs, contents match")
        table.add_column(justify="left", header="hidden")
        for mtime_file in only_mtime_differs_files:
            hidden = hide_reason_by_file_path.get(mtime_file.path)
            last_indexed = format_age(time.time() - mtime_file.stored_stat.mtime)
            table.add_row(last_indexed, str(mtime_file.display_path), hidden)
        console.print(table)

    if deleted_files:
        deleted_files.sort(key=lambda x: x.stored_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="deleted files")
        table.add_column(justify="left", header="hidden")
        for deleted_file in deleted_files:
            hidden = hide_reason_by_file_path.get(deleted_file.path)
            last_indexed = format_age(time.time() - deleted_file.stored_stat.mtime)
            table.add_row(last_indexed, str(deleted_file.display_path), hidden)
        console.print(table)
