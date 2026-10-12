Tips on a failure:
- Split bigger patches into smaller patches
- Watch out for whitespace differences

### More exmaples

Here's a patch file to change the type of `win`:

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

This can be simplified to:

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

Or, if the `win` property is globally unique:

```diff
*** Begin Patch
*** Update File: src/gap.py
@@
-    win: GapWindow
+    win: SilenceWindow
*** End Patch
```
