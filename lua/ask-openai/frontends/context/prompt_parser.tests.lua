local prompt_parser = require("ask-openai.frontends.context.prompt_parser")
local instructs = require("ask-openai.frontends.instructs")
require('ask-openai.helpers.testing')
local describe = require("devtools.tests.define.describe")

describe("class ParseIncludes", function()
    it("new returns object with get_reasoning_level() function", function()
        local includes = prompt_parser.Includes.new({ reasoning_low = true })
        assert.is_function(includes.get_reasoning_level)
        assert.are_equal("low", includes:get_reasoning_level())
    end)
end)

describe("register_replacement_command", function()
    it("registers a command and replaces it during render", function()
        local test_replacer_called = false
        prompt_parser.register_replacement_command("/test_replace", function()
            test_replacer_called = true
            return "REPLACED_VALUE"
        end)
        
        local includes = prompt_parser.render("/test_replace foo bar")
        assert.is_true(test_replacer_called, "replacer function should be called when command is present")
        assert.are_equal("REPLACED_VALUE foo bar", includes.rendered_prompt)
    end)

    it("does not call replacer if command is absent (lazy evaluation)", function()
        local test_replacer_called = false
        prompt_parser.register_replacement_command("/test_lazy", function()
            test_replacer_called = true
            return "SHOULD_NOT_APPEAR"
        end)
        
        local includes = prompt_parser.render("foo bar")
        assert.is_false(test_replacer_called, "replacer function should NOT be called when command is absent")
        assert.are_equal("foo bar", includes.rendered_prompt)
    end)

    it("handles multiple occurrences of registered command", function()
        local count = 0
        prompt_parser.register_replacement_command("/test_multi", function()
            count = count + 1
            return "VAL"
        end)
        
        local includes = prompt_parser.render("/test_multi foo /test_multi bar /test_multi")
        assert.are_equal(1, count, "replacer should only be called once per render cycle")
        assert.are_equal("VAL foo VAL bar VAL", includes.rendered_prompt)
    end)

    it("respects word boundaries for registered command", function()
        local test_replacer_called = false
        prompt_parser.register_replacement_command("/test_bound", function()
            test_replacer_called = true
            return "BOUND_VAL"
        end)
        
        local includes = prompt_parser.render("foo/test_bound bar")
        assert.is_false(test_replacer_called, "replacer should not be called without word boundary")
        assert.are_equal("foo/test_bound bar", includes.rendered_prompt)
    end)
end)

describe("render", function()
    describe("static", function()
        function ensure_detects(command, field)
            field = field or command
            describe("/" .. command, function()
                -- test slash command detection when the command appears at various positions
                local position_cases = {
                    { scenario = "start of prompt",                   prompt = "/" .. command .. " foo bar" },
                    { scenario = "start of prompt + spaces before",   prompt = "  /" .. command .. " foo bar" },
                    { scenario = "middle of prompt",                  prompt = "foo /" .. command .. " bar" },
                    { scenario = "end of prompt",                     prompt = "foo bar /" .. command },
                    { scenario = "end of prompt + spaces after",      prompt = "foo bar /" .. command .. "  " },
                    --
                    { scenario = "unchanged b/c on end of word",      prompt = "bar/" .. command,             unchanged = true },
                    { scenario = "unchanged b/c in middle of a word", prompt = "foo/" .. command .. "bar",    unchanged = true },
                    { scenario = "unchanged b/c in front of word",    prompt = "/" .. command .. "Foo",       unchanged = true },
                    --
                    -- * duplicate /command => strips all
                    -- FYI dup is a conundrum => only an issue if hits 2/3 of my gsub() calls...
                    --    else duplicates would be all trimmed w/in the same case (start gsub / middle gsub / end gsub)
                    --    basically I am covering edge cases of my implementation
                    --    TODO try tokenizing the prompt => get rid of whitespace headache?
                    {
                        scenario = "command duplicated - middle + end",
                        prompt = "foo bar /" .. command .. " /" .. command,
                    },
                    {
                        scenario = "command duplicated - start + middle",
                        prompt = "/" .. command .. " /" .. command .. " foo bar",
                    },
                    {
                        scenario = "command duplicated - start + end",
                        prompt = "/" .. command .. " foo bar /" .. command,
                    },
                    {
                        scenario = "command duplicated - start + middle + end",
                        prompt = "/" .. command .. " foo /" .. command .. " bar /" .. command
                    },
                }

                for _, case in ipairs(position_cases) do
                    it(case.scenario .. ": `" .. case.prompt .. "`", function()
                        local includes = prompt_parser.render(case.prompt)
                        if case.unchanged then
                            assert.is_false(includes[field], "includes." .. field .. " should be false")
                            assert.are_equal(case.prompt, includes.rendered_prompt)
                        else
                            assert.is_true(includes[field], ("includes.%s should be true"):format(field))
                            -- PRN remove? hack to ignore leading/trailing spaces on rendered_prompt
                            local rendered_prompt = includes.rendered_prompt:gsub("^%s+", ""):gsub("%s+$", "")
                            assert.are_equal("foo bar", rendered_prompt)
                        end
                    end)
                end
            end)
        end

        -- just add one test per, do not exercise tests of the parsing/stripping
        ensure_detects("yanks")

        -- reasoning level control (i.e. so can set this in instructs!)
        ensure_detects("low", "reasoning_low")
        ensure_detects("medium", "reasoning_medium")
        ensure_detects("high", "reasoning_high")
        ensure_detects("off", "reasoning_off")

        ensure_detects("commits")
        ensure_detects("file", "current_file")
        ensure_detects("WIP_open_files", "open_files")
        ensure_detects("selection", "include_selection")
        ensure_detects("tools", "use_tools")
        ensure_detects("readonly")
        ensure_detects("WIP_template", "apply_template_only")
        ensure_detects("norag")
    end)

    describe("extract /k", function()
        local function expect(scenario, prompt)
            it(scenario, function()
                local includes = prompt_parser.render(prompt)
                assert.are_equal(3, includes.top_k)
                assert.are_equal("foo bar", includes.rendered_prompt)
            end)
        end

        expect("start of prompt", "/k=3 foo bar")
        expect("start of prompt + spaces before", "  /k=3 foo bar")
        expect("middle of prompt", "foo /k=3 bar")
        expect("end of prompt", "foo bar /k=3")
        expect("end of prompt + spaces after", "foo bar /k=3  ")

        it("without /k => returns prompt as is", function()
            local top_k, prompt = prompt_parser.strip_patterns_from_prompt("foo bar")
            assert.is_nil(top_k)
            assert.are_equal("foo bar", prompt)
        end)

        it("without word boundary => does not parse", function()
            local top_k, prompt = prompt_parser.strip_patterns_from_prompt("foo/k=3 bar")
        end)
    end)

    describe("/cwd", function()
        it("replaces /cwd with cwd at start of prompt", function()
            local cwd = vim.fn.getcwd()
            local includes = prompt_parser.render("/cwd foo bar")
            assert.are_equal(cwd .. " foo bar", includes.rendered_prompt)
        end)

        it("replaces /cwd with cwd in middle of prompt", function()
            local cwd = vim.fn.getcwd()
            local includes = prompt_parser.render("foo /cwd bar")
            assert.are_equal("foo " .. cwd .. " bar", includes.rendered_prompt)
        end)

        it("replaces /cwd with cwd at end of prompt", function()
            local cwd = vim.fn.getcwd()
            local includes = prompt_parser.render("foo bar /cwd")
            assert.are_equal("foo bar " .. cwd, includes.rendered_prompt)
        end)

        it("replaces multiple /cwd occurrences", function()
            local cwd = vim.fn.getcwd()
            local includes = prompt_parser.render("/cwd foo /cwd bar /cwd")
            assert.are_equal(cwd .. " foo " .. cwd .. " bar " .. cwd, includes.rendered_prompt)
        end)

        it("does not replace /cwd without word boundary", function()
            local includes = prompt_parser.render("foo/cwd bar")
            assert.are_equal("foo/cwd bar", includes.rendered_prompt)
        end)

        it("handles /cwd with leading whitespace", function()
            local cwd = vim.fn.getcwd()
            local includes = prompt_parser.render("  /cwd foo bar")
            assert.are_equal(cwd .. " foo bar", includes.rendered_prompt)
        end)

        it("handles /cwd with trailing whitespace", function()
            local cwd = vim.fn.getcwd()
            local includes = prompt_parser.render("foo bar /cwd  ")
            assert.are_equal("foo bar " .. cwd, includes.rendered_prompt)
        end)
    end)

    describe("instructs", function()
        local fake_name = "fake_poo"
        instructs.cached_instruct_slash_commands = { fake_name }
        -- instructs._instruct_paths_by_name[instruct_name] = "/fake/instructy/poo" -- not required if injecting content into cache

        it("should detect and load instruct commands", function()
            instructs._instruct_contents_by_name[fake_name] = "INJECTED INSTRUCTY POO"
            local includes = prompt_parser.render("foo /" .. fake_name .. " bar")
            assert.are_equal("foo bar\nINJECTED INSTRUCTY POO", includes.rendered_prompt)
        end)

        local function ensure_static_slash_command_is_identified(command, field)
            -- print(command)
            field = field or command
            it("/" .. command, function()
                instructs._instruct_contents_by_name[fake_name] = "INJECTED INSTRUCTY POO /" .. command
                local includes = prompt_parser.render("foo /" .. fake_name .. " bar")
                assert.is_true(includes[field], "includes." .. field .. " should be true due to /" .. command .. " in instruct content")
                assert.are_equal("foo bar\nINJECTED INSTRUCTY POO", includes.rendered_prompt)
            end)
        end

        describe("support static slash commands", function()
            local cases = {
                { "all" },
                { "yanks" },
                { "commits" },
                { "file",           "current_file" },
                { "WIP_open_files", "open_files" },
                { "tools",          "use_tools" },
                { "readonly" },
                { "WIP_template",   "apply_template_only" },
                { "selection",      "include_selection" },
                { "norag" },
            }

            for _, case in ipairs(cases) do
                local command, field = case[1], case[2]
                ensure_static_slash_command_is_identified(command, field)
            end
        end)


        it("should detect top_k embedded in instruct content", function()
            local top_k_val = 7
            instructs._instruct_contents_by_name[fake_name] = "INJECTED INSTRUCTY POO /k=" .. top_k_val
            local includes = prompt_parser.render("foo /" .. fake_name .. " bar")
            assert.are_equal(top_k_val, includes.top_k, "top_k should be parsed as 7")
            assert.are_equal("foo bar\nINJECTED INSTRUCTY POO", includes.rendered_prompt)
        end)
    end)
end)
