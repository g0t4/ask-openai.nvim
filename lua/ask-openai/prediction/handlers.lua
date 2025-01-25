local M = {}

function M.ask_for_prediction()
    print("Asking for prediction...")
end

function M.reject()
    print("Rejecting prediction...")
end

function M.accept_all()
    print("Accepting all predictions...")
end

function M.accept_line()
    print("Accepting line prediction...")
end

function M.accept_word()
    print("Accepting word prediction...")
end

return M
