
from rank_bm25 import BM25Okapi

# %%

documents = [
    "The quick brown fox jumps over the lazy dog.",
    "Never go over the fence quickly.",
    "Foo the bar",
]

bm25 = BM25Okapi([doc.split() for doc in documents])

bm25.get_scores("never jump over the lazy dog".split(" "))

# %%
#

corpus = [
    "Hello there good man!",
    "It is quite windy in London",
    "How is the weather today?",
    "The man flashed the bus with a high five",
]
bm25 = BM25Okapi([doc.split() for doc in corpus])

bm25.get_scores("windy London".split(" "))
