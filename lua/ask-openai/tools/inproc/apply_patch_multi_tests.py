import sys
from io import StringIO
from pathlib import Path
import importlib.util
import importlib.machinery

import pytest

def load_module():
    """Load the apply_patch_multi module from its source file."""
    module_path = Path(__file__).parent / "apply_patch_multi.py"
    loader = importlib.machinery.SourceFileLoader("apply_patch_multi", str(module_path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod

def test_de_dupe_in_middle_between_multiple_patches(monkeypatch, capsys):
    # key parts:
    # 1. two Ends in the middle (with a Begin after)...
    #    ensure replace two Ends with one End doesn't mess up splitting out second Patch block
    # 2. ends with multiple End Patch lines... make sure they collapse into one
    #    last one has no \n at end of line, curveball too
    # 3. two Patch blocks, must be split apart and echo'd back what they will do
    #
    # FYI careful, don't try to patch this file ;)
    content = ("""*** Begin Patch
*** Add File: foo.py
+ foo
*** End Patch
*** End Patch
*** Begin Patch
*** Add File: bar.py
+ bar
*** End Patch
*** End Patch
*** End Patch""")
    monkeypatch.setattr(sys, "stdin", StringIO(content))
    monkeypatch.setattr(sys, "argv", ["apply_patch_multi.py", "--dry-run"])

    mod = load_module()
    mod.main()

    out = capsys.readouterr().out
    assert "Found 2 patch blocks" in out
    assert """*** Begin Patch
*** Add File: foo.py
+ foo
*** End Patch
*** Begin Patch
*** Add File: bar.py
+ bar
*** End Patch


Found 2 patch blocks, running one at a time...
## Applying patch #1:
*** Begin Patch
*** Add File: foo.py
+ foo
*** End Patch


## Applying patch #2:
*** Begin Patch
*** Add File: bar.py
+ bar
*** End Patch

""" in out

    # print(out)
