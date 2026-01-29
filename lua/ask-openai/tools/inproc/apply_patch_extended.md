Tips on a failure:

- You only need enough context for a unique match!
- The line(s) you replace are context too; if they’re unique, no additional context is needed.
- Split bigger patches into smaller patches, i.e. if editing two functions, try each separately!
- Watch out for whitespace differences, i.e. blank lines

Please be curteous:

- NEVER leave comments about removed code, just get rid of it. This code lives in a git repo.
- Check your work! Especially after a failure.

## More Examples

Here's a patch file to change the `win` property's type:

```diff
*** Begin Patch
*** Update File: src/gap.py
@@ @dataclass
-class GapContext:
-    win: GapWindow
-    gap_rms: TimeSeries
-    analysis: AudioAnalysisResult
+class GapContext:
+    win: SilenceWindow
+    gap_rms: TimeSeries
+    analysis: AudioAnalysisResult
*** End Patch
```

Which can be simplified to:

```diff
*** Begin Patch
*** Update File: src/gap.py
@@
-class GapContext:
-    win: GapWindow
+class GapContext:
+    win: SilenceWindow
*** End Patch
```

Or, this could work if the `win` property is unique:

```diff
*** Begin Patch
*** Update File: src/gap.py
@@
-    win: GapWindow
+    win: SilenceWindow
*** End Patch
```
