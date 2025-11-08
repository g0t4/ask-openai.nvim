-- harmony_parser.lua
-- Incremental parser for OpenAI Harmony messages (subset: no tool calls).
-- Parses streamed deltas like <|start|>assistant<|channel|>final<|message|>Hello<|end|>

local HarmonyParser = {}
HarmonyParser.__index = HarmonyParser

function HarmonyParser.new()
  local self = setmetatable({}, HarmonyParser)
  self.buffer = ""
  self.messages = {}
  self.current = nil
  return self
end

-- Internal: push current message and reset
local function finish_message(self)
  if self.current then
    table.insert(self.messages, self.current)
    self.current = nil
  end
end

-- Internal: parse a header segment like "assistant<|channel|>analysis"
local function parse_header(header)
  local role, channel = header:match("^(.-)<|channel|>(.-)$")
  if not role then
    role = header
  end
  return {
    role = role:match("^%s*(.-)%s*$"),
    channel = channel and channel:match("^%s*(.-)%s*$") or nil,
  }
end

-- Process as many complete tokens as available
local function process_buffer(self)
  while true do
    local s_start = self.buffer:find("<|start|>", 1, true)
    if not s_start then
      -- no new message start; see if there's an open message continuing
      if self.current and self.buffer ~= "" then
        self.current.content = self.current.content .. self.buffer
        self.buffer = ""
      end
      return
    end

    -- discard anything before start marker
    if s_start > 1 then
      self.buffer = self.buffer:sub(s_start)
    end

    -- try to find <|message|>
    local msg_sep = self.buffer:find("<|message|>", s_start + 9, true)
    if not msg_sep then return end

    local header = self.buffer:sub(s_start + 9, msg_sep - 1)
    local meta = parse_header(header)

    local end_pos = self.buffer:find("<|end|>", msg_sep + 11, true)
    if not end_pos then
      -- incomplete message; buffer until we see <|end|>
      if not self.current then
        self.current = {
          role = meta.role,
          channel = meta.channel,
          content = self.buffer:sub(msg_sep + 11),
        }
        self.buffer = ""
      end
      return
    end

    local content = self.buffer:sub(msg_sep + 11, end_pos - 1)
    table.insert(self.messages, {
      role = meta.role,
      channel = meta.channel,
      content = content,
    })

    self.buffer = self.buffer:sub(end_pos + 7)
  end
end

-- Public: feed in deltas
function HarmonyParser:add_delta(delta)
  if not delta then return end
  local chunk = type(delta) == "table" and (delta.content or delta.text) or delta
  if type(chunk) ~= "string" or chunk == "" then return end
  self.buffer = self.buffer .. chunk
  process_buffer(self)
end

function HarmonyParser:get_messages()
  -- flush any trailing partial message
  if self.current then
    table.insert(self.messages, self.current)
    self.current = nil
  end
  local msgs = self.messages
  self.messages = {}
  return msgs
end

return HarmonyParser

