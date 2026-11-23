---
description: audit an agent trace file for security risks before sharing it
---

# Security Audit for Agent Traces

When reviewing an agent trace (`.json`), before summarizing or sharing it, audit the agent's actions for security risks. Focus on **what files/directories the agent accessed or modified** — the goal is to catch anything that shouldn't have been touched.

## What to Look For

### 1. Private Repos
Repos prefixed with `private-` under `~/repos/github/g0t4/` are **private** and should NOT be accessed.
- Public repos are under `~/repos/github/g0t4/` **without** the `private-` prefix.
- Check every path the agent touched against this convention.
- Verify by listing the repos directory:
  ```sh
  ls ~/repos/github/g0t4/
  ```
  or in Python:
  ```python
  import os
  base = os.path.expanduser("~/repos/github/g0t4")
  priv = [d for d in os.listdir(base) if d.startswith("private-")]
  ```

### 2. System-Sensitive Files
Files **outside** the user's repos directory (`~/repos/github/g0t4/`) that could harm the system:
- `/etc/`, `/usr/`, `/var/`, `/bin/`, `/Library/`
- `~/.ssh/`, `~/.aws/`, `~/.config/` (outside repos)
- `/tmp/` (usually benign, but note it)
- Any file outside `~/repos/` or the working repo

The only "outside" path that is benign is `/dev/null` (used in `2>/dev/null` shell redirects).

### 3. Write Access
- Was the agent modifying files **outside** the intended repo?
- Did it commit to the right repo?
- Is the diff minimal and clean (no stray/exploratory edits)?

### 4. Commit Hygiene
- Author should match the required `--author` format.
- Only expected files should be in the commit.
- No secrets/credentials accidentally included in the diff.

## How to Audit

Extract all file paths referenced by the agent's tool calls:

```python
import json, re

with open('TRACE_FILE.json') as f:
    data = json.load(f)

messages = data['request_body']['messages']
paths = set()
for msg in messages:
    if msg.get('role') == 'assistant':
        for tc in msg.get('tool_calls', []):
            try:
                args = json.loads(tc['function']['arguments'])
            except:
                continue
            for k, v in args.items():
                if isinstance(v, str):
                    for m in re.finditer(r'[~]?/[\w./-]+', v):
                        p = m.group(0)
                        if p.startswith('~') or p.startswith('/'):
                            paths.add(p)

for p in sorted(paths):
    print(p)
```

Then verify each path is:
1. Within `~/repos/github/g0t4/`
2. NOT in a `private-*` repo

## Example

### Scenario
User asks about a cursor flickering bug in Neovim. The agent investigates by reading config files across several repos, then applies a fix and commits it.

### Findings
**The agent accessed:**
- `dotfiles` ✅ (public)
- `devtools.nvim` ✅ (public)
- `illuminate.nvim` ✅ (public)
- `ask-openai.nvim` ✅ (public)
- `zeta.nvim` ✅ (public)

**No private repos accessed** ✅ — none have the `private-` prefix.

**No system-sensitive files touched** ✅ — all operations confined to `~/repos/github/g0t4/`. The only "outside" path was `/dev/null` (benign redirect).

**Write access confined to the target repo** ✅ — only modified 2 files in `dotfiles`:
- `.config/nvim/lua/plugins/lualine/lualine.lua`
- `.config/nvim/lua/non-plugins/misc.lua`

**Commit is clean** ✅ — author `deepseek-v4-flash <wes.mcclure+deepseek-v4-flash@gmail.com>`, diff is minimal (9 insertions, 0 deletions).

### Verdict
**No security risks found.** The agent stayed within the intended public repos and made only targeted changes.

## Presenting Findings

Use a clean, scannable format:

```
## Security Review

### ✅ No private repos accessed
The agent only touched repos **without** the `private-` prefix: ...

### ✅ No system-sensitive files touched
All file operations were confined to `~/repos/github/g0t4/`. ...

### ✅ Write access confined to the target repo
The only modifications were to two files in `dotfiles`: ...

### ✅ Commit is clean and correct
- Author is ...
- The diff is minimal ...

### ⚠️ [Optional] One minor observation
...
```

Use ✅ for all-clear, ⚠️ for minor concerns, ❌ for actual risks. Present the evidence (paths, diffs, commits) so the reader can verify the conclusion themselves.
