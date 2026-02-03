from pathlib import Path
from rank_bm25 import BM25Okapi

documents = [
    "refresh auth token logic",
    "token expiration handler",
    "user login authentication",
]

tokenized_docs = [doc.split() for doc in documents]
bm25 = BM25Okapi(tokenized_docs)

query = "token refresh"
scores = bm25.get_scores(query.split())

# %%

from whoosh.fields import Schema, TEXT, ID
from whoosh.analysis import StandardAnalyzer

schema = Schema(
    chunk_id=ID(stored=True, unique=True),
    # path=ID(stored=True),
    content=TEXT(analyzer=StandardAnalyzer()),
)

# %%

from whoosh.index import create_in

index_dir = ".bm25"
Path(index_dir).mkdir(parents=True, exist_ok=True)

ix = create_in(index_dir, schema)

# %%

writer = ix.writer()

for i, doc in enumerate(documents):
    print(i, doc)
    writer.add_document(
        chunk_id=str(i),
        content=doc,
        # path=chunk["path"],
    )

writer.commit()
