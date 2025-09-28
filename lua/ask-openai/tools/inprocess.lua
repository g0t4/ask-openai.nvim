local M = {}

-- In-process tools would be added here
-- For now, we'll just have the basic structure

local function hello_new_tool()
    print("Hello new tool!")
    return "Hello from the new in-process tool!"
end

local M = {}

---@class ToolDefinition
---@field name string
---@field description string
---@field inputSchema table

M.tools_available = {
    rag_query = {
        name = "rag_query",
        description = "Query RAG for code and documents in the current workspace",
        inputSchema = {
            type = "object",
            properties = {
                query = {
                    type = "string",
                    description = "The query to send to the RAG system"
                },
                instruct = {
                    type = "string",
                    description = "Optional instruct to provide context for the query"
                },
                top_k = {
                    type = "number",
                    description = "Top K results to return"
                },
                embed_top_k = {
                    type = "number",
                    description = "Number of embeddings to consider for reranking"
                }
            },
            required = { "query" }
        }
    }
}


---@param tool_name string
---@return boolean
function M.handles_tool(tool_name)
    local tool = M.tools_available[tool_name]
    return tool ~= nil
end

---@param query string
---@return table
local function rag_query_impl(query)
    -- Implementation would go here
    return {
        result = "RAG response for: " .. query
    }
end

---@param tool_call table
---@param callback fun(response: table)
function M.send_tool_call(tool_call, callback)
    local name = tool_call["function"].name

    if name == "rag_query" then
        local args = tool_call["function"].arguments
        local parsed_args = vim.json.decode(args)
        local result = rag_query_impl(parsed_args.query)
        local response = {
            result = result
        }
        callback(response)
        return
    end

    error("in-process tool not implemented yet: " .. name)
end

return M
