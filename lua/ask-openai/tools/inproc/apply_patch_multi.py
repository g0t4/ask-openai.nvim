# this is a stopgap solution for when gptoss generates multiple patches in one patch file
# - no idea why this isn't supported OOB
#   alternatives all entail more instructions to every call to the model:
#   - tell it not to, pray it never does
#   fail if it does and explain in output
#   - then model has to generate again and hopefully that works

# This happens when:
# *** Begin Patch
# ...
# *** End Patch
# *** Begin Patch
# ...
# *** End Patch

import argparse
import re
import subprocess
import sys
from pathlib import Path

# cat lua/ask-openai/tools/inproc/test-multi-patch.patch | python3 lua/ask-openai/tools/inproc/apply_patch_splitter.py

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the patch content without applying it",
    )
    args = parser.parse_args()

    content = sys.stdin.read()

    # de-duplicate consecutive "*** End Patch" lines (collapse into one)
    #  often happens w/ gptoss at the end of a patch file
    #  really no reason not to just ignore this
    #    maybe a sign that the model "forgot" something...
    #    more likely just a mistake in "closing" out the patch
    #    I've noticed this with mutli Patch examples
    content = re.sub(r"(^\*\*\* End Patch$\n*){2,}", "*** End Patch\n", content, flags=re.MULTILINE)  # https://regexr.com/8j95j

    if args.dry_run:
        import rich
        rich.print("[blue]de-dupe End Patch:[/]")
        print(content)
        print()

    apply_patch_rs = Path("~/repos/github/openai/codex/codex-rs/target/release/apply_patch").expanduser()  # https://regexr.com/8j95m
    count_begins = len(re.findall(r"^\*\*\* Begin Patch$", content, flags=re.MULTILINE))
    print(f'{count_begins=}')
    if count_begins <= 1:
        if not args.dry_run:
            subprocess.run([apply_patch_rs], input=content, text=True, check=True)
        return

    # Split the content on each "*** Begin Patch" marker
    # Keep the marker with each subsequent chunk
    raw_patches = re.split(r"(^\*\*\* Begin Patch$)", content, flags=re.MULTILINE)
    # Recombine the split parts so each patch starts with the marker
    patches = []
    for i in range(1, len(raw_patches), 2):
        marker = raw_patches[i]
        body = raw_patches[i + 1] if i + 1 < len(raw_patches) else ""
        patches.append(f"{marker}{body}")

    print(f"Found {count_begins} patch blocks, running one at a time...")

    for i, patch in enumerate(patches, start=1):
        print(f"Applying patch #{i}:")
        for line in patch.split("\n"):
            print(f"  {line}")
        print()
        if not args.dry_run:
            subprocess.run([apply_patch_rs], input=patch, text=True, check=True)

if __name__ == "__main__":
    main()
