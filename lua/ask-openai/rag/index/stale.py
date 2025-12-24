import logging
import humanize
from dataclasses import dataclass
from pathlib import Path
from lsp.storage import Datasets
from lsp.fs import relative_to_workspace
from lsp.chunks.chunker import get_file_stat

logger = logging.getLogger(__name__)

def _format_age(age_seconds: float) -> str:
    days = 24 * 60 * 60
    if age_seconds > 7 * days:
        return f"[red]{humanize.naturaldelta(age_seconds)}[/]"
    if age_seconds > 2 * days:
        return f"[yellow]{humanize.naturaldelta(age_seconds)}[/]"
    return f"[green]{humanize.naturaldelta(age_seconds)}[/]"

@dataclass(frozen=True)
class FileIssue:
    age_seconds: float
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
            age_seconds = abs(stored_stat.mtime - recomputed_stat.mtime)

            hash_match = recomputed_stat.hash == stored_stat.hash

            details_parts: list[str] = []

            if not hash_match:
                # Primary emphasis on age difference
                if age_seconds:
                    age_str = _format_age(age_seconds)
                    details_parts.append(f"age: {age_str}")

                # Size difference
                if recomputed_stat.size != stored_stat.size:
                    size_delta = recomputed_stat.size - stored_stat.size
                    size_str = f"{stored_stat.size}→{recomputed_stat.size}"
                    details_parts.append(f"size: {size_str}")

                # Hash mismatch (least important)
                details_parts.append(f"hash: {stored_stat.hash[:8]}→{recomputed_stat.hash[:8]}")
                changed.append(FileIssue(age_seconds, display_path, "; ".join(details_parts)))
            else:
                # Hash matches; only consider mtime difference
                if age_seconds:
                    age_str = _format_age(age_seconds)
                    details_parts.append(f"age: {age_str}")

                    mtime_only.append(FileIssue(age_seconds, display_path, "; ".join(details_parts)))

    # Sort groups by descending age
    mtime_only.sort(key=lambda x: x.age_seconds, reverse=True)
    changed.sort(key=lambda x: x.age_seconds, reverse=True)

    # Report mtime‑only differences
    for issue in mtime_only:
        logger.warning(f"Stale {issue.display_path}: {issue.details}")

    # Report changed files
    for issue in changed:
        logger.warning(f"Changed {issue.display_path}: {issue.details}")
