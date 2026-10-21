describe("backend discovery", function()
    local original_system, original_client, original_discovery
    before_each(function()
        original_system = vim.system
        original_client = package.loaded["ask-openai.backends.llama_cpp.llama_server_client"]
        original_discovery = package.loaded["ask-openai.backends.discovery"]
        package.loaded["ask-openai.backends.discovery"] = nil
    end)
    after_each(function()
        vim.system = original_system
        package.loaded["ask-openai.backends.llama_cpp.llama_server_client"] = original_client
        package.loaded["ask-openai.backends.discovery"] = original_discovery
    end)
    it("probes asynchronously, detects servers, rejects stale responses and clears failures", function()
        package.loaded['ask-openai.backends.llama_cpp.llama_server_client'] = {
         extract_model_info = function(body) local m = (body.data or {})[1]; return m and { name = m.id } end,
        }
        local requests = {}
        vim.system = function(args, opts, cb) requests[#requests+1] = { url = args[#args], cb = cb } end
        local d = require('ask-openai.backends.discovery')
        local function respond(index, body, status)
         requests[index].cb({code=0, stdout=vim.json.encode(body)..'\n'..(status or '200')})
         vim.wait(50, function() return false end, 10)
        end
        d.refresh('http://test'); assert(#requests == 1)
        assert(d.get('http://test').name == 'Pending...')
        respond(1, {data={{id='test',owned_by='vllm'}}})
        assert(d.get('http://test').backend == 'vllm'); assert(#requests == 1)
        d.refresh('http://test'); d.refresh('http://test')
        respond(3, {data={{id='new',owned_by='llamacpp'}}})
        respond(2, {data={{id='old',owned_by='vllm'}}})
        assert(d.get('http://test').model_info.name == 'new')
        d.refresh('http://test'); respond(4, {data={{id='ambiguous'}}})
        assert(requests[5].url == 'http://test/props')
        respond(5, {default_generation_settings={}})
        assert(d.get('http://test').backend == 'llama-server')
        d.refresh('http://test'); respond(6, {data={{id='ambiguous'}}})
        respond(7, {}, '404'); respond(8, {info={title='vLLM'}})
        assert(d.get('http://test').backend == 'vllm')
        d.refresh('http://test'); respond(9, {}, '503')
        assert(d.get('http://test').name == 'FETCH_FAILED')

    end)
end)
