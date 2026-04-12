## Comments in prompts

- Use markdown comments to strip out parts of a prompt at runtime
- Use sed or lua pattern to strip
   `sed '/<!--/,/-->/d'`
- PRN add `skills_src` with commented originals, use a generate step to build (strip out comments)
  - BONUS, I could compose/template sections across skills that should be reused
    (i.e. if two skills need to refer to GNU vs BSD command differences => run_process + refactor_shell_longoptions)
