dots_module = {
    dots = "",
    count = 0,
    still_thinking = function()
        dots_module.count = dots_module.count + 1
        if dots_module.count % 4 == 0 then
            dots_module.dots = dots_module.dots .. "."
        end
        if dots_module.count > 120 then
            dots_module.dots = ""
            dots_module.count = 0
        end
    end,
}
