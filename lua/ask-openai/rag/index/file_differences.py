import logging
import time
from dataclasses import dataclass
from pathlib import Path
from rich.table import Table
from rich.console import Console

from config.domains import find_files_by_semantic_domain
from index.storage import Datasets, FileStat
from index import workspace
from chunks.chunker import get_file_stat

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
    display_path: Path
    current_stat: FileStat


@dataclass(frozen=True)
class StaleFile:
    """An indexed file whose stored hash differs from current hash."""
    display_path: Path
    stored_stat: FileStat
    current_stat: FileStat


@dataclass(frozen=True)
class MtimeOnlyFile:
    """An indexed file with only mtime difference (hash matches)."""
    display_path: Path
    stored_stat: FileStat
    current_stat: FileStat


@dataclass(frozen=True)
class DeletedFile:
    """An indexed file that no longer exists on disk."""
    display_path: Path
    stored_stat: FileStat


def warn_about_file_differences(datasets: Datasets, root_dir: Path) -> None:
    """Warn about files that differ between the index and the filesystem.

    Compares indexed files against all files found via semantic domain matching.
    Reports: added (unindexed), stale (hash mismatch), mtime-only, and deleted files.
    """
    source_code_dir = root_dir
    files_by_domain = find_files_by_semantic_domain(source_code_dir)

    # Build a set of all indexed file stats
    all_index_stats: dict[str, FileStat] = {}
    for dataset in datasets.all_datasets.values():
        all_index_stats.update(dataset.stat_by_path)

    # Build a set of all actual files
    all_disk_files: dict[str, FileStat] = {}
    for domain_files in files_by_domain.values():
        for path in domain_files:
            all_disk_files[path] = get_file_stat(path)

    added_files: list[AddedFile] = []
    content_differs: list[StaleFile] = []
    mtime_only_files: list[MtimeOnlyFile] = []
    deleted_files: list[DeletedFile] = []

    # * indexed files comparison
    for path_str, index_stat in all_index_stats.items():
        display_path = workspace.get_relative_path_to(path_str, override_root_path=root_dir)

        # * deleted files
        if path_str not in all_disk_files:
            deleted_files.append(DeletedFile(display_path, index_stat))
            continue

        disk_stat = all_disk_files[path_str]
        hash_differs = disk_stat.hash != index_stat.hash

        # * content differs
        if hash_differs:
            content_differs.append(StaleFile(display_path, index_stat, disk_stat))
            continue

        # * mtime differes
        mtime_differs = abs(index_stat.mtime - disk_stat.mtime) > 0
        if mtime_differs:
            mtime_only_files.append(MtimeOnlyFile(display_path, index_stat, disk_stat))

    # * added files
    for path_str, disk_stat in all_disk_files.items():
        if path_str not in all_index_stats:
            display_path = workspace.get_relative_path_to(path_str, override_root_path=root_dir)
            added_files.append(AddedFile(display_path, disk_stat))

    if not (added_files or content_differs or mtime_only_files or deleted_files):
        logger.info("[bold green]All files are in sync — no differences found![/]")
        return

    console = Console()
    console.print()
    console.print("[bold white]FILE DIFFERENCES:[/]")
    console.print("[italic]  run [bold]rag_indexer[/bold] to update the index...[/]\n")

    # Added files (not yet indexed)
    if added_files:
        added_files.sort(key=lambda x: x.current_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="age", header_style="not bold white italic")
        table.add_column(justify="left", header="added (not yet indexed)")
        for added_file in added_files:
            file_age = time.time() - added_file.current_stat.mtime
            age_str = format_age(file_age)
            table.add_row(age_str, str(added_file.display_path))
        console.print(table)

    # Stale files (hash mismatch)
    if content_differs:
        content_differs.sort(key=lambda x: x.stored_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="path")
        table.add_column(justify="left", header="size")
        table.add_column(justify="left", header="hash")
        for stale_file in content_differs:
            last_indexed = format_age(time.time() - stale_file.stored_stat.mtime)

            if stale_file.current_stat.size != stale_file.stored_stat.size:
                delta = stale_file.current_stat.size - stale_file.stored_stat.size
                sign = "+" if delta > 0 else "-"
                size_str = f"{sign}{abs(delta)}"
            else:
                size_str = ""

            hash_str = f"{stale_file.stored_stat.hash[:8]}→{stale_file.current_stat.hash[:8]}"
            table.add_row(last_indexed, str(stale_file.display_path), size_str, hash_str)
        console.print(table)

    # Mtime-only files (hash matches, mtime differs)
    if mtime_only_files:
        mtime_only_files.sort(key=lambda x: x.stored_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="only mtime differs, contents match")
        for mtime_file in mtime_only_files:
            last_indexed = format_age(time.time() - mtime_file.stored_stat.mtime)
            table.add_row(last_indexed, str(mtime_file.display_path))
        console.print(table)

    # Deleted files
    if deleted_files:
        deleted_files.sort(key=lambda x: x.stored_stat.mtime, reverse=True)
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="deleted files")
        for deleted_file in deleted_files:
            last_indexed = format_age(time.time() - deleted_file.stored_stat.mtime)
            table.add_row(last_indexed, str(deleted_file.display_path))
        console.print(table)
