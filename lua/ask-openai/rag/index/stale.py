import logging
import humanize
from dataclasses import dataclass
from pathlib import Path
from rich.table import Table
from rich.console import Console
from lsp.storage import Datasets, FileStat
from lsp.fs import relative_to_workspace
from lsp.chunks.chunker import get_file_stat

logger = logging.getLogger(__name__)

def format_age(age_seconds: float) -> str:
    days = 24 * 60 * 60
    if age_seconds > 7 * days:
        return f"[red]{humanize.naturaldelta(age_seconds)}[/]"
    if age_seconds > 2 * days:
        return f"[yellow]{humanize.naturaldelta(age_seconds)}[/]"
    return f"[green]{humanize.naturaldelta(age_seconds)}[/]"

@dataclass(frozen=True)
class FileIssue:
    mtime_diff: float
    display_path: Path
    stored_stat: FileStat
    new_stat: FileStat

def warn_about_stale_files(datasets: Datasets, root_dir: Path) -> None:
    mtime_only: list[FileIssue] = []
    changed: list[FileIssue] = []
    deleted_files: list[Path] = []

    for dataset in datasets.all_datasets.values():
        for path_str, stored_stat in dataset.stat_by_path.items():
            file_path = Path(path_str)
            display_path = relative_to_workspace(file_path, override_root_path=root_dir)
            if not file_path.is_file():
                deleted_files.append(display_path)
                continue

            new_stat = get_file_stat(file_path)
            mtime_diff = abs(stored_stat.mtime - new_stat.mtime)

            if not new_stat.hash == stored_stat.hash:
                changed.append(FileIssue(mtime_diff, display_path, stored_stat, new_stat))
            elif mtime_diff:
                mtime_only.append(FileIssue(mtime_diff, display_path, stored_stat, new_stat))

    # console.print(table) is fine for now, this is not run in backend (not yet)
    console = Console()

    if any(deleted_files):
        deleted_files.sort()
        table = Table(width=100)
        table.add_column(justify="left", header="deleted files")
        for file in deleted_files:
            table.add_row(str(file))
        console.print(table)
        console.print()

    if any(mtime_only):
        mtime_only.sort(key=lambda x: x.mtime_diff, reverse=True)

        console.print()
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="only mtime differs, contents match")
        for issue in mtime_only:
            age = format_age(issue.mtime_diff)
            table.add_row(age, str(issue.display_path))
        console.print(table)
        console.print()

    if any(changed):
        changed.sort(key=lambda x: x.mtime_diff, reverse=True)

        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="path")
        table.add_column(justify="left", header="size")
        table.add_column(justify="left", header="hash")
        for issue in changed:
            age = format_age(issue.mtime_diff)
            if issue.new_stat.size != issue.stored_stat.size:
                size_str = f"{issue.stored_stat.size}→{issue.new_stat.size}"
            else:
                size_str = ""
            hash_str = f"{issue.stored_stat.hash[:8]}→{issue.new_stat.hash[:8]}"
            table.add_row(age, str(issue.display_path), size_str, hash_str)
        console.print(table)
        console.print()
