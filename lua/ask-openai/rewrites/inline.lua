local function get_visual_selection()
  local _, start_line, start_col, _ = unpack(vim.fn.getpos("'<"))
  local _, end_line, end_col, _ = unpack(vim.fn.getpos("'>"))
  local lines = vim.fn.getline(start_line, end_line)

  if #lines == 0 then return "" end

  lines[#lines] = string.sub(lines[#lines], 1, end_col)
  lines[1] = string.sub(lines[1], start_col)

  return vim.fn.join(lines, "\n")
end

local function ask_user_with_selection()
  local selected = get_visual_selection()
  local input = vim.fn.input("Enter your prompt: ")
  print("User prompt: " .. input)
  print("Selected text:\n" .. selected)
  -- You can now use `input` and `selected` as needed
end

vim.api.nvim_create_user_command("AskPrompt", ask_user_with_selection, {range=true})

