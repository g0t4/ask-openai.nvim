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

# for now I just want to split on Begin Patch
# and then call apply_patch for each

# read over STDIN

import subprocess
import sys
import re

# cat lua/ask-openai/tools/inproc/test-multi-patch.patch | python3 lua/ask-openai/tools/inproc/apply_patch_splitter.py

def main() -> None:
    # Read all input from STDIN
    content = sys.stdin.read()

    count_begins = len(re.findall(r"^\*\*\* Begin Patch$", content, re.MULTILINE))
    if count_begins <= 1:
        subprocess.run(["apply_patch"], input=content, text=True, check=True)
        return

    # Split the content on each "*** Begin Patch" marker
    # Keep the marker with each subsequent chunk
    raw_patches = re.split(r"(\*\*\* Begin Patch)", content)
    # Recombine the split parts so each patch starts with the marker
    patches = []
    for i in range(1, len(raw_patches), 2):
        marker = raw_patches[i]
        body = raw_patches[i + 1] if i + 1 < len(raw_patches) else ""
        patches.append(f"{marker}{body}")

    print(f"Found {count_begins} patch blocks, running one at a time...")

    for i, patch in enumerate(patches, start=1):
        print(f"Applying patch #{i}...")
        subprocess.run(["apply_patch"], input=patch, text=True, check=True)

if __name__ == "__main__":
    main()
