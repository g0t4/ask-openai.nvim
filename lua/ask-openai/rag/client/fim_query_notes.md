## query/instruct selection for RAG in a FIM tool context

- TODO look into what research has been done too
- Repoformer - apparently they have policies for when to use RAG and not within FIM

```lua

-- baseline (first query) I tried
local query = short_prefix .. "<<<FIM CURSOR HERE>>>" .. short_suffix -- OLD query format
-- issue is, using full (or mostly full) FIM prompt (PSM)
--   leads RAG results to reflect prominent code nearby
--   the FIM completion task does not stand out to the embed/rerankers...
--   IOTW nearby, prominent code distracts from FIM code (cursor position)
--   might be interesting to fine tune embed/re-rankers on FIM? and see if this can improve with a specialized model... b/c then you would maybe have best of both worlds (surrounding context plus FIM focus)

-- SO, for now, I want to try other styles to get focus back onto the FIM task

-- tried swapping <<<...>>> for actual fim token for cursor position <|fim_middle|> to no avail
local query = short_prefix .. "<|fim_middle|>" .. short_suffix

-- Then, I tried using the full fim PSM format directly, instead of generic <<<FIM CURSOR HERE>>>
--  this seemed to suffer from similar distractions
--  IOTW the format of the FIM prompt (prefix/suffix/cursor position-aka middle) doesn't correct focus to FIM
local query = "<|fim_prefix|>" .. short_prefix .. "<|fim_suffix|>" .. short_suffix .. "<|fim_middle|>"

-- NEXT IDEA, which works in one case and is smth I was thinking of for a while now...
-- ONLY include the current line's prefix! (and maybe disable RAG if no current line context!)
-- I tested this hypothesis with one scenario and it panned out...
-- this comes from the intution that RAG doesn't need much to find what you want
--   and if variables are named well, i.e. ip below => IndentPrinter class is embedded in variable name so you don't need prior lines to see when ip was constructed!
--   so let's try this for a while and see how well I feel it performs in daily tasks...
--   might not work well either!
local query = "ip.incremen" -- UGH this finds what I want! lol... but neither of the following work!

-- WHY lop off the suffix?
--   same=> can be distracting beyond current line
--   even for current line, that's mostly needed to know when to stop the generation (EOS)
--   BUT, PRN, fair game to try adding current line suffix too

-- TODO skip RAG if no text on current line? or < minimum (i.e. 5 or so?)
--   PRN OR revert to full FIM if current line has no text (or < min)?

-- TODO a next idea: use a small model (qwen2.5-coder-0.5B or 1.5B) and have it generate a Semantic Grep from the full FIM prompt! then use that... should be sub 10/20ms to do this
--  quantized model too, no no p
```
