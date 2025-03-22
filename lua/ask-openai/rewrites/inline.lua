local function get_visual_selection()
  local _, start_line, start_col, _ = unpack(vim.fn.getpos("'<"))
  local _, end_line, end_col, _ = unpack(vim.fn.getpos("'>"))
  local lines = vim.fn.getline(start_line, end_line)

  if #lines == 0 then return "" end

  lines[#lines] = string.sub(lines[#lines], 1, end_col)
  lines[1] = string.sub(lines[1], start_col)

  return vim.fn.join(lines, "\n")
end

local function ask_and_send_to_ollama()
  local code = get_visual_selection()
  local user_prompt = vim.fn.input("Prompt: ")

  local data = {
    prompt = user_prompt .. "\n\nCode:\n" .. code,
    model = "qwen2.5-coder:7b-instruct-q8_0",
    stream = false,
    -- TODO STREAM THE RESPONSE!?
    temperature = 0.2
  }

  local json = vim.fn.json_encode(data)
  local response = vim.fn.system({
    "curl", "-s", "-X", "POST", "http://ollama:11434/api/generate",
    "-H", "Content-Type: application/json",
    "-d", json
  })

  local parsed = vim.fn.json_decode(response)
  if parsed and parsed.response then
    vim.fn.setreg("+", parsed.response)
    print("Completion copied to clipboard!")
  else
    print("Failed to get response from Ollama.")
  end
end

vim.api.nvim_create_user_command("OllamaTransform", ask_and_send_to_ollama, {range=true})
