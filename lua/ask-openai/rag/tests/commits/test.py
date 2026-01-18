import subprocess
from datetime import datetime
from rich import print
from types import SimpleNamespace

class AttrList(list):

    def __init__(self, *args, **kwargs):
        super().__init__(*args)
        self.__dict__.update(kwargs)

    def __getattr__(self, key):
        return self.__dict__[key]

    def __setattr__(self, key, value):
        self.__dict__[key] = value

    def __repr__(self):
        attr_repr = ", ".join(f"{k}={v!r}" for k, v in self.__dict__.items())
        list_items = "\n        ".join(repr(x) for x in self)
        return f"AttrList({attr_repr})\n    [\n        {list_items}\n    ]"

# print(AttrList(['a', 'b'], c='d'))

def build_frecency_from_git():
    # Get commits with file stats
    git_log = subprocess.run(
        ['git', 'log', '--numstat', '--pretty=format:%H|%at|%an', '--since=6 months ago'],
        capture_output=True,
        text=True,
    )

    frecency_data = {}
    for line in git_log.stdout.split('\n'):
        if '|' in line:  # Commit info
            commit_hash, timestamp, author = line.split('|')
        elif '\t' in line:  # File changes
            adds, dels, filepath = line.split('\t')

            if filepath not in frecency_data:
                frecency_data[filepath] = AttrList()

            frecency_data[filepath].append(SimpleNamespace(
                timestamp=int(timestamp),
                author=author,
                changes=int(adds) + int(dels),
                commit=commit_hash,
            ))
    return frecency_data

def git_frecency(commits, half_life_days=14):
    score = 0
    for commit in commits:
        print(commit)
        days_ago = (datetime.now().timestamp() - commit.timestamp) / (24 * 3600)
        # commit_weight = commit.changes  # Or just 1 for presence
        commit_weight = 1
        decay = 0.5**(days_ago / half_life_days)
        score += commit_weight * decay
    return score

if __name__ == "__main__":
    frecency_data = build_frecency_from_git()
    for file in frecency_data:
        print(file)
        file_score = git_frecency(frecency_data[file])
        frecency_data[file].score = file_score
    # Save to file or process as needed
    # with open('git_frecency_data.json', 'w') as f:
    #     json.dump(frecency_data, f)

    print()
    print(frecency_data)
    print()

    # sort
    # FYI looking at this reminds me I care WAY more about recency than frequency!
    #  make recency dominate the scoring only frequency only matters for similarly recent files
    sorted_files = sorted(frecency_data.items(), key=lambda x: x[1].score, reverse=True)
    for file, data in sorted_files:
        print(f"{file}: {data.score}")

# could do multisignal frecency ... i.e.
# def code_frecency(file_data):
#     # Different decay rates for different signals
#     edit_score = exponential_decay(file_data.edit_count, file_data.last_edit, 0.1)
#     view_score = exponential_decay(file_data.view_count, file_data.last_view, 0.05)
#     rag_score = exponential_decay(file_data.rag_matches, file_data.last_rag_match, 0.2)
#
#     return edit_score * 0.5 + view_score * 0.3 + rag_score * 0.2
