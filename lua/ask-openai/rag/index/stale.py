    def warn_about_stale_files(self, datasets: Datasets, root_dir: Path) -> None:

        mtime_only: list[tuple[float, str, str]] = []  # (age_seconds, display_path, details)
        changed: list[tuple[float, str, str]] = []  # (age_seconds, display_path, details)

        def _format_age(age_seconds: int) -> str:
            days = 24 * 60 * 60
            if age_seconds > 7 * days:
                return f"[red]{humanize.naturaldelta(age_seconds)}[/]"
            if age_seconds > 2 * days:
                return f"[yellow]{humanize.naturaldelta(age_seconds)}[/]"
            return f"[green]{humanize.naturaldelta(age_seconds)}[/]"

        for dataset in datasets.all_datasets.values():
            for path_str, stored_stat in dataset.stat_by_path.items():
                file_path = Path(path_str)
                display_path = relative_to_workspace(file_path, override_root_path=root_dir)
                if not file_path.is_file():
                    logger.warning(f"Index file deleted? [red strike]{display_path}[/]")
                    continue

                recomputed_stat = get_file_stat(file_path)
                age_seconds = abs(stored_stat.mtime - recomputed_stat.mtime)

                # Determine hash match
                hash_match = recomputed_stat.hash == stored_stat.hash

                # Build detail string
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
                    entry = (age_seconds, display_path, "; ".join(details_parts))
                    changed.append(entry)
                else:
                    # Hash matches; only consider mtime difference
                    if age_seconds:
                        age_str = _format_age(age_seconds)
                        details_parts.append(f"age: {age_str}")

                        entry = (age_seconds, display_path, "; ".join(details_parts))
                        mtime_only.append(entry)

        # Sort groups by descending age
        mtime_only.sort(key=lambda x: x[0], reverse=True)
        changed.sort(key=lambda x: x[0], reverse=True)

        # Report mtime‑only differences
        for _, display_path, details in mtime_only:
            logger.warning(f"Stale {display_path}: {details}")

        # Report changed files
        for _, display_path, details in changed:
            logger.warning(f"Changed {display_path}: {details}")


