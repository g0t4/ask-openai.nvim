## zed embeddings

### TODO

- find a way to get it to index some code?
- is there a search tool builtin to zed now (I see semantic search in the zed codebase)
- or is this just for chat completions? and/or predictions

### Observations

- WIP Zeta2 context
    - *** https://github.com/zed-industries/zed/pull/38372
    - zeta appears to be getting an update see Zeta2Request (WIP) just from 3 days ago
    - ~/repos/github/zed-industries/zed/crates/edit_prediction_context
        - change includes similarity scoring
    - ~/repos/github/zed-industries/zed/crates/edit_prediction_context/src/wip_requests.rs

- woa => deepwiki is a great way to summarize what a codebase is doing! uses devin
    https://deepwiki.com/search/what-does-this-app-do-with-emb_5b86643f-c264-44b5-b838-070f2d7305ca
    can ask about things

- uses openai compat endpoint for embeddings
    - presumably works with llama-server?

### Implementation details

- language specific treesitter queries
    - i.e. for c: https://github.com/zed-industries/zed/blob/main/crates/languages/src/c/embedding.scmL12
      crates/languages/src/c/embedding.scm
      crates/languages/src/javascript/embedding.scm
      crates/languages/src/jsonc/embedding.scm
      crates/languages/src/go/embedding.scm
      crates/languages/src/typescript/embedding.scm
      crates/languages/src/rust/embedding.scm
      crates/languages/src/tsx/embedding.scm
      crates/languages/src/python/embedding.scm
      crates/languages/src/cpp/embedding.scm
      crates/languages/src/json/embedding.scm

## migrations?

~/repos/github/zed-industries/zed/crates/collab/migrations/20240409082755_create_embeddings.sql

CREATE TABLE IF NOT EXISTS "embeddings" (
    "model" TEXT,
    "digest" BYTEA,
    "dimensions" FLOAT4[1536],
    "retrieved_at" TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY ("model", "digest")
);

CREATE INDEX IF NOT EXISTS "idx_retrieved_at_on_embeddings" ON "embeddings" ("retrieved_at");

### database

- seems like its merged with zed collab feature
    - https://github.com/zed-industries/zed/blob/main/crates/collab/src/db/tables.rs#L13
    - must be a remote db?
- TODO is this the latest db location? found in my .config dir, didn't look at their code yet
    - sqlite db in ~/.config/zed/embeddings/
- Also found this:
    - embeddings/semantic-index-db.0.mdb/
    lmdb
    `mdb_dump embeddings/semantic-index-db.0.mdb`

```sql
CREATE TABLE files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    worktree_id INTEGER NOT NULL, -- * worktree == absolute_path
    relative_path VARCHAR NOT NULL,
    mtime_seconds INTEGER NOT NULL, -- * file modification timestamp, presumably to re-index
    mtime_nanos INTEGER NOT NULL,
    FOREIGN KEY(worktree_id) REFERENCES worktrees(id) ON DELETE CASCADE
);
```

```sql
CREATE TABLE worktrees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    absolute_path VARCHAR NOT NULL
);
-- TLDR absolute path to the worktree, then relative paths within, in the files table
```

```sql
CREATE TABLE semantic_index_config (
    version INTEGER NOT NULL
);
-- IIAC this database's migrations ID
```

```sql
CREATE TABLE spans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id INTEGER NOT NULL,

    -- * offsets in bytes, per treesitter queries
    start_byte INTEGER NOT NULL,
    end_byte INTEGER NOT NULL,

    -- TODO what is the name? is it a summary or? do they search on this?
    name VARCHAR NOT NULL,

    -- * presumably the vector:
    --   TODO what do they use for vector search?
    embedding BLOB NOT NULL,

    digest BLOB NOT NULL,
    FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE
);
CREATE INDEX spans_digest ON spans (digest);
```
