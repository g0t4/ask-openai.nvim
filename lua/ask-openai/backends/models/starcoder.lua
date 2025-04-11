local M = {}

-- Table 5 -
-- <|endoftext|> end of text/sequence
-- <fim_prefix> FIM prefix
-- <fim_middle> FIM middle
-- <fim_suffix> FIM suffix
-- <fim_pad> FIM pad
-- <repo_name> repository name
-- <file_sep> file separator
-- <issue_start> start of GitHub issue
-- <issue_comment> start of GitHub issue comment
-- <issue_closed> GitHub issue closed event
-- <jupyter_start> start of Jupyter notebook
-- <jupyter_text> start of Jupyter text cell
-- <jupyter_code> start of Jupyter code cell
-- <jupyter_output> start of Jupyter output cell
-- <jupyter_script> start of Jupyter script (converted kaggle notebook)
-- <empty_output> output cell without content
-- <code_to_intermediate> translate source code to intermediate representation
-- <intermediate_to_code> translate intermediate representation to source code
-- <pr> start of pull request
-- <pr_status> status of pull request
-- <pr_is_merged> whether pr is merged
-- <pr_base> start of list of base files
-- <pr_file> path of pull request file
-- <pr_base_code> code that is part of the base commit in the PR
-- <pr_diff> start of a diff
-- <pr_diff_hunk> diff hunk
-- <pr_comment> general comment
-- <pr_event_id> GitHub id of review comment or code review comment
-- <pr_review> start of review
-- <pr_review_state> review state (e.g. approved, rejected)
-- <pr_review_comment> code review comment
-- <pr_in_reply_to_review_id> GitHub event id of review
-- <pr_in_reply_to_comment_id> GitHub event id of comment
-- <pr_diff_hunk_comment_line> line number of code review comment

M.starcoder2 = {
    sentinel_tokens = {
        fim_prefix = "<fim_prefix>",
        fim_middle = "<fim_middle>",
        fim_suffix = "<fim_suffix>",
        fim_pad = "<fim_pad>",
        repo_name = "<repo_name>",
        file_sep = "<file_sep>",
        -- TODO others:
        issue_start = "<issue_start>",
        issue_comment = "<issue_comment>",
        issue_closed = "<issue_closed>",
        jupyter_start = "<jupyter_start>",
        jupyter_text = "<jupyter_text>",
        jupyter_code = "<jupyter_code>",
        jupyter_output = "<jupyter_output>",
        jupyter_script = "<jupyter_script>",
        empty_output = "<empty_output>",
        code_to_intermediate = "<code_to_intermediate>",
        intermediate_to_code = "<intermediate_to_code>",
        pr = "<pr>",
        pr_status = "<pr_status>",
        pr_is_merged = "<pr_is_merged>",
        pr_base = "<pr_base>",
        pr_file = "<pr_file>",
        pr_base_code = "<pr_base_code>",
        pr_diff = "<pr_diff>",
        pr_diff_hunk = "<pr_diff_hunk>",
        pr_comment = "<pr_comment>",
        pr_event_id = "<pr_event_id>",
        pr_review = "<pr_review>",
        pr_review_state = "<pr_review_state>",
        pr_review_comment = "<pr_review_comment>",
        pr_in_reply_to_review_id = "<pr_in_reply_to_review_id>",
        pr_in_reply_to_comment_id = "<pr_in_reply_to_comment_id>",
        pr_diff_hunk_comment_line = "<pr_diff_hunk_comment_line>",

        -- im_start = "<im_start>", -- UNSURE
        -- im_end = "<im_end>", -- UNSURE
        endoftext = "<|endoftext|>" -- only one with pipes too
    },
}

return M
