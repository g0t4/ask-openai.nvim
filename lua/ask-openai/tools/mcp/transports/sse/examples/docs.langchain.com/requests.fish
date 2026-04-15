#!/usr/bin/env fish

curl https://docs.langchain.com/mcp > mcp.json
# cat mcp.json | jq .resources

# references what appears to be this mintlify KB about langchain:
#    https://langchain-ai-langchain.mintlify.app/introduction
#    which interestingly if I change URL to /mcp:
#        https://langchain-ai-langchain.mintlify.app/mcp
#        which looks alot like the initial capabilities.json from above!
# the block w/o `user-agent` header?!
#   curl https://langchain-ai-langchain.mintlify.app/mcp > mintlify_mcp.json
# w/ faux user agent it works:
curl 'https://langchain-ai-langchain.mintlify.app/mcp' \
  -H 'user-agent: Chrome' > mintlify_mcp.json
#  TODO RETURN TO this mintlify MCP endpoint... I suspect it is the same (or close to the same) as docs.langchain.com/mcp



