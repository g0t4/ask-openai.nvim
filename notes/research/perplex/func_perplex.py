from logging import logProcesses
from transformers import AutoModelForCausalLM, AutoTokenizer
import torch, math

# func1 = """
# function M.reusable_curl_seam(body, url, frontend, extract_generated_text, backend)
func1 = """
    local request = LastRequest:new(body)

    body.stream = true
    local json = vim.json.encode(body)
    log:json_info("body:", json)

    local options = {
        command = "curl",
        args = {
            "--fail-with-body",
            "-sSL",
            "--no-buffer", -- w/o this curl batches (test w/ `curl *` vs `curl * | cat` and you will see difference)
            "-X", "POST",
            url,
            "-H", "Content-Type: application/json",
            "-d", json
        },
    }
    -- -- PRN use configuration/caching for this (various providers from original cmdline help feature)
    -- -- for now, just uncomment this when testing:
    -- api_key = os.getenv("OPENAI_API_KEY")
    -- if api_key then
    --     table.insert(options.args, "-H")
    --     table.insert(options.args, "Authorization: Bearer " .. api_key)
    -- end

    -- PRN could use bat -l sh for this one:
    -- log:warn("curl args: ", table.concat(options.args, " "))

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)

    options.on_exit = function(code, signal)
        log:trace_on_exit_always(code, signal)
        -- log:trace_on_exit_errors(code, signal) -- less verbose

        if code ~= nil and code ~= 0 then
            log:error("spawn - non-zero exit code: '" .. code .. "' Signal: '" .. signal .. "'")
            -- DO NOT add frontend handler just to have it log again!
        else
            frontend.curl_request_exited_successful_on_zero_rc()
        end
        stdout:close()
        stderr:close()

        -- this shoudl be attacked to a specific request (not any module)
        -- clear out refs
        request.handle = nil
        request.pid = nil
    end

    request.handle, request.pid = uv.spawn(options.command, {
        args = options.args,
        stdio = { nil, stdout, stderr },
    }, options.on_exit)


    function data_value_handler(data_value)
        -- TODO extract error handling: both the xpcall + traceback, and the print_error func below
        -- FYI good test case is to comment out: choice.delta.content == vim.NIL in extract_generated_text
        local success, result = xpcall(function()
            M.on_line_or_lines(data_value, extract_generated_text, frontend, request)
        end, function(e)
            -- otherwise only get one line from the traceback (frame that exception was thrown)
            return debug.traceback(e, 3)
        end)

        if not success then
            M.terminate(request)

            -- FAIL EARLY, accept NO unexpected exceptions in completion parsing
            -- by the way the request will go a bit longer but it will stop ASAP
            -- important part is to alert me
            log:error("Terminating curl_streaming due to unhandled exception", result)

            local function print_error(message)
                -- replace literals so traceback is pretty printed (readable)
                message = tostring(message):gsub("\\n", "\n"):gsub("\\t", "\t")
                -- with traceback lines... this will trigger hit-enter mode
                --  therefore the error will not disappear into message history!
                -- ErrorMsg makes it red
                vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, {})
            end

            vim.schedule(function()
                print_error("Terminating curl_streaming due to unhandled exception" .. tostring(result))
            end)
        end
    end

    -- PRN request._sse_parser = parser -- currently closure is sufficient for all expected use cases
    local parser = SSEStreamParser.new(data_value_handler)
    options.on_stdout = function(read_error, data)
        -- log:trace_stdio_read_errors("on_stdout", err, data)
        log:trace_stdio_read_always("on_stdout", read_error, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            -- reminder, rely on trace above
            return
        end

        parser:write(data)
    end
    uv.read_start(stdout, options.on_stdout)

    options.on_stderr = function(read_error, data)
        log:trace_stdio_read_always("on_stderr", read_error, data)
        -- log:trace_stdio_read_errors("on_stderr", err, data)

        local no_data = data == nil or data == ""
        if read_error or no_data then
            -- reminder, rely on trace above
            return
        end

        -- keep in mind... curl errors will show as text in STDERR
        frontend.on_stderr_data(data)
    end
    uv.read_start(stderr, options.on_stderr)

    return request
"""
# end
# """

# %%

device = torch.device("mps")
# model = "Qwen/Qwen2.5-0.5B"  # * non coder variant! useful to see prediction differences (i.e. perplexity diffs!)
model = "Qwen/Qwen2.5-Coder-0.5B"
tok = AutoTokenizer.from_pretrained(model)
model = AutoModelForCausalLM.from_pretrained(model, torch_dtype=torch.float16).eval()
model.to(device)  # type: ignore

# %%

from indent_print import IndentPrinter

def perplexity_from_logits(code):
    ip = IndentPrinter()
    print = ip.print
    inputs = tok(code, return_tensors="pt").to(device)
    print(f'{inputs=}')
    ip.increment()
    for i in inputs.input_ids[0]:
        print(i)
        print(tok.decode(i))
    ip.decrement()
    print("\nout:")
    with torch.no_grad():
        out = model(**inputs)
        print(f'{out=}')
    ip.increment()
    total_perplex = 0
    for idx, logits in enumerate(out.logits[0]):
        # * input
        print(f'\n{idx}')
        input_token = inputs.input_ids[0][idx].item()
        input_txt = tok.decode(input_token)
        input_value = logits[input_token].item()
        ip.increment()
        print(f'{input_token=} {input_value=} "{input_txt}"')
        #
        # * pred next token (highest probability)
        max_idx = torch.argmax(logits).item()
        max_value = logits[max_idx].item()
        max_pred = tok.decode(max_idx)
        print(f'{max_idx=} {max_value=} "{max_pred}"')
        #
        # * normalize values
        min_value = torch.min(logits)
        print(f'{min_value=}')
        # norm_logits = (logits - min_value) / (max_value - min_value)
        shifted_to_zero_max = logits - max_value
        print(f'{torch.min(shifted_to_zero_max)=}')  #
        print(f'{torch.max(shifted_to_zero_max)=}')  #
        #
        # * exp e^x ... collapses all values from 0 to 1 (NOT NORMALIZED YET, but closer!)
        exp = torch.exp(shifted_to_zero_max)
        print(f'{torch.min(exp)=}')  # 0 min (as x=>-infinity, y=>0... IOTW e^-infinity = 0)
        print(f'{torch.max(exp)=}')  # 1 max (e^0 = 1)
        exp_sum = torch.sum(exp)
        print(f'{exp_sum=}')  # obviously not 1 yet!
        softmax = exp / exp_sum
        # * softmax normalization complete:
        print(f'{torch.min(softmax)=}')  # min >= 0
        print(f'{torch.max(softmax)=}')  # max <= 1 - hints at perplexity, max closer to 1 => high confidence (low perplexity), small max (i.e. 0.1) => low confidence (high perplexity)
        print(f'{torch.sum(softmax)=}')  # s/b 1 (normalized)
        #
        #
        # ENSURE sm == softmax (approx)
        sm = torch.softmax(logits, dim=-1)
        print(f'  {torch.min(sm)=}')  # min >= 0
        print(f'  {torch.max(sm)=}')  # max <= 1 - hints at perplexity, max closer to 1 => high confidence (low perplexity), small max (i.e. 0.1) => low confidence (high perplexity)
        print(f'  {torch.sum(sm)=}')  # s/b 1 (normalized)
        #
        log_softmax = torch.log(softmax)
        print(f'{torch.min(log_softmax)=}')  # min >= 0
        print(f'{torch.max(log_softmax)=}')  # max <= 1 - hints at perplexity, max closer to 1 => high confidence (low perplexity), small max (i.e. 0.1) => low confidence (high perplexity)
        print(f'{torch.sum(log_softmax)=}')  # s/b 1 (normalized)
        log_sm = torch.log(sm)
        print(f'  {torch.min(log_sm)=}')  # min >= 0
        print(f'  {torch.max(log_sm)=}')  # max <= 1 - hints at perplexity, max closer to 1 => high confidence (low perplexity), small max (i.e. 0.1) => low confidence (high perplexity)
        print(f'  {torch.sum(log_sm)=}')  # s/b 1 (normalized)
        #
        # FYI log_softmax AIO helps avoid rounding errors that lead to -infinity on lowest probabilit(ies)
        log_sm_aio = torch.nn.functional.log_softmax(logits, dim=-1)
        print(f'  {torch.min(log_sm_aio)=}')
        print(f'  {torch.max(log_sm_aio)=}')
        print(f'  {torch.sum(log_sm_aio)=}')
        #
        exp_log_probs = torch.exp(log_softmax)
        print(f'{torch.min(exp_log_probs)=}')
        print(f'{torch.max(exp_log_probs)=}')
        print(f'{torch.sum(exp_log_probs)=}')
        #
        # * actual next token
        if idx < len(inputs.input_ids[0]) - 1:
            actual_next_token = inputs.input_ids[0][idx + 1]
            print(f'{actual_next_token=}')
            prob_actual_next_token = log_sm_aio[actual_next_token]
            neg_prob_of_actual_next_token = -prob_actual_next_token
            print(f'{neg_prob_of_actual_next_token=}')
            total_perplex += neg_prob_of_actual_next_token
            print(f'{total_perplex=} (avg: {total_perplex/(idx+1)})')
        #
        #
        ip.decrement()
    ip.decrement()

#
simple = "local request = LastRequest:new(body)"  # 6.49357 (using loss directly)
perplexity_from_logits(simple)  # 6.49609375 (avg)

# %%

def line_perplexity_from_loss(lines):
    line_losses = []
    # PRN? SKIP COMMENTS!?
    for line in lines:
        print(line)
        line = line.strip()
        if not line:  # skip empty lines
            line_losses.append(None)
            continue
        inputs = tok(line, return_tensors="pt").to(device)
        with torch.no_grad():
            out = model(**inputs, labels=inputs.input_ids)
        if torch.isfinite(out.loss):
            line_losses.append(out.loss.item())
            continue
        line_losses.append(None)
    return line_losses

print(f"simple perplex: {line_perplexity_from_loss([simple])}")  # 6.49357

# %%
import rich

# Example usage
lines = func1.split("\n")
line_perplexities = line_perplexity_from_loss(lines)
print(f'{line_perplexities=}')

perplexities_skip_none = [p for p in line_perplexities if p is not None]
print(f'{perplexities_skip_none}')
perplexities_tensor = torch.tensor(perplexities_skip_none)
lines_mean = torch.mean(perplexities_tensor)
lines_std = torch.std(perplexities_tensor)
rich.print(f'{lines_mean=} {lines_std=}')

alpha_spike_factor = 1.0
for idx, line in enumerate(lines):
    perplex = line_perplexities[idx]
    threshold = alpha_spike_factor * lines_std + lines_mean
    if perplex is not None and perplex > threshold:
        line = "*" + line[1:]
        rich.print(f"[red]{idx+1}: {line}         {perplex}[/red]")
    else:
        rich.print(f"{idx+1}: {line}        {perplex}")
