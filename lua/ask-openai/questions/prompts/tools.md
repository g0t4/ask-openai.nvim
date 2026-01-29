## Tool use

For tool use, never modify files outside of the current working directory unless the user requested it:
INSERT_CWD

## Use `semantic_grep` to find code

The semantic_grep tool:

- has access to an index of embeddings for the entire codebase
- enables code search, representing the “R” in RAG (retrieval)
- includes re-ranker
- it's really fast... so don't hesitate to use it!
- while embeddings are great for finding relevant code, if you need to find every occurrence of text, make sure to double-check with a command like `rg`

