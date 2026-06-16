import math, re
from collections import Counter

def tokenize(text):
    return re.findall(r"\w+", text.lower())

class BM25:
    def __init__(self, docs, k1=1.5, b=0.75):
        self.docs = [tokenize(d) for d in docs]
        self.N = len(docs)
        self.avgdl = sum(len(d) for d in self.docs) / self.N
        self.k1, self.b = k1, b

        # per-doc term freqs and lengths
        self.term_freqs = [Counter(d) for d in self.docs]
        self.doc_lens = [len(d) for d in self.docs]

        # document frequencies
        df = Counter()
        for tf in self.term_freqs:
            for t in tf:
                df[t] += 1
        self.idf = {t: math.log((self.N - n + 0.5) / (n + 0.5) + 1e-12) for t, n in df.items()}

    def score(self, query):
        q = tokenize(query)
        scores = [0.0] * self.N
        for i, tf in enumerate(self.term_freqs):
            dl = self.doc_lens[i]
            denom_norm = self.k1 * (1 - self.b + self.b * dl / self.avgdl)
            s = 0.0
            for t in q:
                if t not in tf:
                    continue
                f = tf[t]
                idf = self.idf.get(t, 0.0)
                s += idf * (f * (self.k1 + 1)) / (f + denom_norm)
            scores[i] = s
        return scores

# --- example ---
docs = [
    "Neovim plugin for semantic grep and RAG.",
    "BM25 is a strong lexical baseline for keyword search.",
    "Dense embeddings help when queries are paraphrased."
]
bm = BM25(docs)
scores = bm.score("bm25 keyword rag")
ranked = sorted(enumerate(scores), key=lambda x: x[1], reverse=True)
print(ranked)  # [(doc_index, score), ...]

