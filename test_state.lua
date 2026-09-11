local M = {}
local test_sync = ya.sync(function(state)
    state.hello = "world"
    return true
end)
function M:test()
    test_sync()
    print("M.hello =", self.hello)
end
return M
