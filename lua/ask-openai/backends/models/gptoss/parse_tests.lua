

-- add tests for each interesting example in the cookbook:
--   https://cookbook.openai.com/articles/openai-harmony
--   FOCUS on model response scenarios, for parsing (model output side)...
--   - you don't need to parse the system/developer messages (those are input only for your case)
--   - some messages if you don't need to modify them, can just be copy/pasted into chat history for next turns
--
--  {"properties":{"items":{"type":"array","description":"entries on the shopping list","items":{"type":"string"}}},"type":"object"}<|end|><|start|>user<|message|>I need to buy coffee, soda and eggs<|end|><|start|>assistant


