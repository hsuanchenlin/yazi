local M = {}
M.view = function(text) print("view", text) end
local show = ya.sync(function(self, text)
    ya.async(function() self.view(text) end)
end)
