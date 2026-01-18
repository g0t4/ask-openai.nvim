-- FYI docs:
--    guide: https://github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md
--    https://github.com/nvim-lua/plenary.nvim/blob/master/README.md#plenarytest_harness
--
-- busted style testing of nvim... (in floating window OR new instance(s))
--   :PlenaryBustedFile tests/test.lua
--   :PlenaryBustedDirectory tests
--
-- nvim --headless -c "PlenaryBustedDirectory tests/plenary/ {options}"


describe("some basics", function()
    local bello = function(boo)
        return "bello " .. boo
    end

    local bounter

    before_each(function()
        bounter = 0
    end)

    it("some test", function()
        bounter = 100
        assert.equals("bello Brian", bello("Brian"))
    end)

    it("some other test", function()
        assert.equals(0, bounter)
    end)
end)
