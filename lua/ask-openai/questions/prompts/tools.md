## Tool use

For tool use, never modify files outside of the current working directory unless the user requested it:
INSERT_CWD

Here are noteworthy commands you have access to:
- fd, rg, gsed, gawk, jq, yq, httpie
- exa, icdiff, ffmpeg, imagemagick, fzf

Recommendations:
- Prefer `rg` over `grep`
- Prefer `fd` over `find` and `ls -R`

The semantic_grep tool:
- has access to an index of embeddings for the entire codebase in the current working directory
- use it to find code! Think of it as a RAG query tool
- It includes a re-ranker to sort the results
- AND, it's really fast... so don't hesitate to use it!
