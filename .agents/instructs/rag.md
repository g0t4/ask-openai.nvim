## RAG entryoints

### indexer

- builds/rebuilds the index of embeddings for a repo
- entrypoint: `lua/ask-openai/rag/indexer.py`
- tests:
  - `cd ./lua/ask-openai/rag`
  - `ptw **/*_tests.py` to run all tests
  - `ptw indexer_tests.py` for key index build/rebuild integration tests, will rebuild an actual index in `.rag` in the `rag` dir

### ask-language-server (RAG/semantic_grep language server)

- built with `pygls`
- entrypoint: `lua/ask-openai/rag/lsp/server.py`
- Used by neovim to provide RAG queries, to update embeddings when files are edited, etc

### MCP server for RAG lua/ask-openai/rag/mcp_server/__main__.py

This can be tested with a few key scripts:
- `./lua/ask-openai/rag/tests/stdio/semantic_grep_list_tools.fish`
  - a good first test is that the server can enumerate tools
- `./lua/ask-openai/rag/tests/stdio/semantic_grep_call_tool.fish`
  - this tests that a RAG query works

### inference server

- entrypoint: `lua/ask-openai/rag/lsp/inference/server/__main__.py`
- runs Qwen3-Embeddings and Qwen3-Reranker models to embed/rerank queries/docs
- can run on any OS but I prefer arch
- custom protocol using MessagePack
  - focused on performance, low latency
  - central instance for embeddings across my network
- clients exist for both python and lua
  - python client is for `indexer`, `ask-language-server`, `MCP RAG server`
  - lua client is for `neovim` (via this repo's ask-openai.nvim neovim plugin)
    - for automatic RAG context in several AI tools: copilot predictions, rewriting code, and agent harness
    - also agents can use `semantic_grep` tool to perform adhoc queries
