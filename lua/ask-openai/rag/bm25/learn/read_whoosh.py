from whoosh.qparser import QueryParser
from whoosh.index import open_dir
from whoosh import query, scoring

ix = open_dir(".bm25")

searcher = ix.searcher(weighting=scoring.BM25F())
parser = QueryParser("content", ix.schema)

def query_it(what):
    query = parser.parse(what)
    results = searcher.search(query, limit=20)

    for hit in results:
        print(hit["chunk_id"], hit.score)

query_it("token refresh")
query_it("token")
query_it("user")
