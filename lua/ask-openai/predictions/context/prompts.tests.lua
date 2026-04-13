local prompts = require("ask-openai.predictions.context.prompts")
local skills = require("ask-openai.frontends.skills")
require('ask-openai.helpers.testing')
local describe = require("devtools.tests._describe")

describe("render", function()
    describe("/all", function()
        local function should_detect_slash_all(original_prompt, expected_cleaned)
            local includes = prompts.render(original_prompt)
            assert.is_true(includes.all, "includes.all should be true for '" .. original_prompt .. "'")
            assert.are_equal(expected_cleaned, includes.rendered_prompt)
        end
        it("'/all' slash command is detected and stripped", function()
            should_detect_slash_all("foo /all bar", "foo bar")
            should_detect_slash_all("/all foo", "foo")
            should_detect_slash_all("foo /all", "foo")
        end)

        local function should_not_detect_slash_all(original_prompt)
            local includes = prompts.render(original_prompt)
            assert.is_false(includes.all, "includes.all should be false for '" .. original_prompt .. "'")
            assert.are_equal(original_prompt, includes.rendered_prompt)
        end
        it("'/all' alone is not detected - for now b/c that means theres no user prompt!", function()
            -- FYI maybe I want to have this parse and strip? but for now it seems moot to do this without any other prompt text
            should_not_detect_slash_all("/all")
        end)
        it("'/allFoo' - in front of word is not stripped", function()
            should_not_detect_slash_all("/allFoo ")
            should_not_detect_slash_all(" /allFoo ")
            should_not_detect_slash_all(" /allFoo")
            should_not_detect_slash_all("/allFoo")
        end)
        it("'foo/allbar' - in between word is not stripped", function()
            should_not_detect_slash_all("foo/allbar ")
            should_not_detect_slash_all(" foo/allbar ")
            should_not_detect_slash_all(" foo/allbar")
            should_not_detect_slash_all("foo/allbar")
        end)
        it("'bar/all' - at end of word is not stripped", function()
            should_not_detect_slash_all("bar/all ")
            should_not_detect_slash_all(" bar/all ")
            should_not_detect_slash_all(" bar/all")
            should_not_detect_slash_all("bar/all")
        end)
    end)
    describe("static", function()
        function ensure_detects(command, field)
            field = field or command
            describe("/" .. command, function()
                -- test slash command detection when the command appears at various positions
                local position_cases = {
                    { scenario = "start of prompt",                 prompt = "/" .. command .. " foo bar" },
                    { scenario = "start of prompt + spaces before", prompt = "  /" .. command .. " foo bar" },
                    { scenario = "middle of prompt",                prompt = "foo /" .. command .. " bar" },
                    { scenario = "end of prompt",                   prompt = "foo bar /" .. command },
                    { scenario = "end of prompt + spaces after",    prompt = "foo bar /" .. command .. "  " },
                    -- { scenario = "tacked onto end of word",         prompt = "bar/" .. command,             unchanged = true },
                }

                for _, case in ipairs(position_cases) do
                    it(case.scenario .. ": `" .. case.prompt .. "`", function()
                        local includes = prompts.render(case.prompt)
                        assert.is_true(
                            includes[field],
                            ("includes.%s should be true"):format(field)
                        )
                        if case.unchanged then
                            assert.are_equal(case.prompt, includes.rendered_prompt)
                        else
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
                local includes = prompts.render(prompt)
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
            local top_k, prompt = prompts.strip_patterns_from_prompt("foo bar")
            assert.is_nil(top_k)
            assert.are_equal("foo bar", prompt)
        end)

        it("without word boundary => does not parse", function()
            local top_k, prompt = prompts.strip_patterns_from_prompt("foo/k=3 bar")
        end)
    end)

    describe("skills", function()
        local fake_skill_name = "fake_skilly_poo"
        skills.cached_skill_commands = { fake_skill_name }
        -- skills._skill_paths[skill_name] = "/fake/skilly/poo" -- not required if injecting content into cache

        it("should detect and load skill commands", function()
            skills._skill_content_cache[fake_skill_name] = "INJECTED SKILLY POO"
            local includes = prompts.render("foo /" .. fake_skill_name .. " bar")
            assert.are_equal("foo bar\nINJECTED SKILLY POO", includes.rendered_prompt)
        end)

        local function ensure_static_slash_command_is_identified(command, field)
            -- print(command)
            field = field or command
            it("/" .. command, function()
                skills._skill_content_cache[fake_skill_name] = "INJECTED SKILLY POO /" .. command
                local includes = prompts.render("foo /" .. fake_skill_name .. " bar")
                assert.is_true(includes[field], "includes." .. field .. " should be true due to /" .. command .. " in skill content")
                assert.are_equal("foo bar\nINJECTED SKILLY POO", includes.rendered_prompt)
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


        it("should detect top_k embedded in skill content", function()
            local top_k_val = 7
            skills._skill_content_cache[fake_skill_name] = "INJECTED SKILLY POO /k=" .. top_k_val
            local includes = prompts.render("foo /" .. fake_skill_name .. " bar")
            assert.are_equal(top_k_val, includes.top_k, "top_k should be parsed as 7")
            assert.are_equal("foo bar\nINJECTED SKILLY POO", includes.rendered_prompt)
        end)
    end)
end)
