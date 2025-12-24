import logging
import humanize
from dataclasses import dataclass
from pathlib import Path
from rich.table import Table
from rich.console import Console
from lsp.storage import Datasets
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
    details: str

def warn_about_stale_files(datasets: Datasets, root_dir: Path) -> None:
    mtime_only: list[FileIssue] = []
    changed: list[FileIssue] = []

    for dataset in datasets.all_datasets.values():
        for path_str, stored_stat in dataset.stat_by_path.items():
            file_path = Path(path_str)
            display_path = relative_to_workspace(file_path, override_root_path=root_dir)
            if not file_path.is_file():
                logger.warning(f"Index file deleted? [red strike]{display_path}[/]")
                continue

            recomputed_stat = get_file_stat(file_path)
            mtime_diff = abs(stored_stat.mtime - recomputed_stat.mtime)

            hash_match = recomputed_stat.hash == stored_stat.hash

            details_parts: list[str] = []

            if not hash_match:
                # Size difference
                if recomputed_stat.size != stored_stat.size:
                    size_delta = recomputed_stat.size - stored_stat.size
                    size_str = f"{stored_stat.size}→{recomputed_stat.size}"
                    details_parts.append(f"size: {size_str}")

                # Hash mismatch (least important)
                details_parts.append(f"hash: {stored_stat.hash[:8]}→{recomputed_stat.hash[:8]}")
                changed.append(FileIssue(mtime_diff, display_path, "; ".join(details_parts)))
            elif mtime_diff:
                # Hash matches; only consider mtime difference
                mtime_only.append(FileIssue(mtime_diff, display_path, ""))

    mtime_only.sort(key=lambda x: x.mtime_diff, reverse=True)
    changed.sort(key=lambda x: x.mtime_diff, reverse=True)

    # console.print(table) is fine for now, this is not run in backend (not yet)
    console = Console()

    if any(mtime_only):
        console.print()
        table = Table(width=100)
        table.add_column(justify="right", header="last indexed", header_style="not bold white italic")
        table.add_column(justify="left", header="only mtime differs, contents match")
        for issue in mtime_only:
            age = format_age(issue.mtime_diff)
            table.add_row(age, str(issue.display_path))
        console.print(table)
        console.print()

    for issue in changed:
        age = format_age(issue.mtime_diff)
        logger.warning(f"Changed {issue.display_path}: {age} {issue.details}")
