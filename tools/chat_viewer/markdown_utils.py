def split_h2_markdown_sections(text: str) -> "Iterator[str]":
    """Split a markdown string into sections based on H2 headers.

    The function iterates over lines, yielding a new section whenever a line
    starting with ``## `` (H2 markdown header) is encountered. The header line
    itself is included as the first line of the new section. If no H2 headers
    are present, the entire text is yielded as a single section.
    """
    lines = text.splitlines()
    current_section: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if current_section:
                yield "\n".join(current_section)
            current_section = [line]
        else:
            current_section.append(line)
    if current_section:
        yield "\n".join(current_section)

