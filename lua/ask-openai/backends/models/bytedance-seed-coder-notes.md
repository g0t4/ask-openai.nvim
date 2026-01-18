# Seed-Coder notes

- Paper: https://github.com/ByteDance-Seed/Seed-Coder/blob/master/Seed-Coder.pdf

## Repo-level FIM

     * GUESSES for repo level FIM format (i.e. RAG, yanks, etc)
     1 try RepoCoder's format
        ~/repos/github/microsoft/CodeT/RepoCoder/build_prompt.py
     2 try using Qwen's file_sep repo level format (it was working on initial testing)
     3. thread dicussing repo level FIM w.r.t. bytedance seed coder:
       https://github.com/ByteDance-Seed/Seed-Coder/issues/12
       a. idea => cram it all into the FIM
         <[fim-suffix]>File2suffix, File3, File4<[fim-prefix]>File1,File2prefix<[fim-middle]>
         what about file names?

## File-level FIM

format: `<[fim-suffix]>SUFFIX<[fim-prefix]>PREFIX<[fim-middle]>MIDDLE`

## RepoCoder relevant code

### `_build_prompt`

```py
def _build_prompt(self, mode, prompt, top_k_context):
    prepend_context = "# Here are some relevant code fragments from other files of the repo:\n"
    self.seperator = '# ' + '-' * 50
    prepend_context += self.seperator + '\n'
    prepend_blocks = []
    chosen_context = []
    make_block_func = self._make_an_extended_block if mode == CONSTANTS.rg else self._make_a_block
    for retrieved_context in top_k_context[::-1]:
        if len(chosen_context) >= self.max_examples:
            break
        block_str, token_len = make_block_func(retrieved_context)
        if current_token_length + token_len < self.max_retrieval_length:
            prepend_blocks.insert(0, block_str)
            current_token_length += token_len
            chosen_context.append(retrieved_context)
        else:
            continue
    prepend_context += ''.join(prepend_blocks)  # all the blocks already have a line break at the end
    return prepend_context + '\n' + prompt, chosen_context
```

### `make_a_block`

```py
def _make_a_block(self, retrieved_context):
    content, sim_score = retrieved_context
    metadata = content['metadata']

    # put the file path in the comment
    assert metadata[0]['fpath_tuple'][0] == metadata[0]['repo']
    f_paths = ['/'.join(x['fpath_tuple'][1:]) for x in metadata]
    f_paths_str = '\n'.join([f'# {f_path}' for f_path in f_paths])
    f_path_comment = f'# the below code fragment can be found in:'

    # put code lines in the comment
    content_lines = content['context'].splitlines()
    content_lines_comment = [f'# {line}' for line in content_lines]

    # aggregate the comment and the code lines
    block_str = '\n'.join([f_path_comment, f_paths_str, self.seperator] + content_lines_comment + [self.seperator]) + '\n'
    tokenized_block = self.tokenizer.tokenize(block_str)
    token_len = len(tokenized_block)
    return block_str, token_len
```

- BTW, `_make_an_extended_block` seems to expand the code sample to more lines nearby than in the indexed document (outside the vector)
    - TODO verify this is the diff?

From `cat datasets/api_level_completion_1k_context_codegen.test.jsonl  | jq`

```json
{
    "prompt": "from.registry import Registry\n\nPOLICY_REGISTRY = Registry()\nENV_REGISTRY = Registry()\nLEARNER_REGISTRY = Registry()\nCOMM_LEARNER_REGISTRY = Registry()",
    "metadata": {
        "task_id": "opendilab_ACE/199",
        "ground_truth": "SERIAL_COLLECTOR_REGISTRY = Registry()",
        "fpath_tuple": [
            "opendilab_ACE",
            "ding",
            "utils",
            "registry_factory.py"
        ],
        "context_start_lineno": 0,
        "line_no": 6
    }
}
```
