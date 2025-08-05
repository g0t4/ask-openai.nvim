from lsp.model_qwen3_remote import encode_query

query = "logger = <<<FIM>>>"
instruct = "help complete this code"
print(encode_query(query, instruct))
