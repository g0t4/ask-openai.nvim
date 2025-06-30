import subprocess
from rich import print

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
                frecency_data[filepath] = []

            frecency_data[filepath].append({
                'timestamp': int(timestamp),
                'author': author,
                'changes': int(adds) + int(dels),
                'commit': commit_hash,
            })
    return frecency_data

if __name__ == "__main__":
    frecency_data = build_frecency_from_git()
    # Save to file or process as needed
    import json
    # with open('git_frecency_data.json', 'w') as f:
    #     json.dump(frecency_data, f)
    print(frecency_data)
