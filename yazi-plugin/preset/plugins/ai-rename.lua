local M = {}

local NAME_MAX = 255
local STDERR_MAX = 1024

local PROMPT = [[
Suggest a clearer filename for a file currently named %q.
Keep its extension. Reply with the new filename alone: one line, no directory, no quotes, no explanation.
]]

local hovered = ya.sync(function()
	local h = cx.active.current.hovered
	return h and h.name or nil
end)

function M:entry()
	local name = hovered()
	if not name then
		return M.notify("warn", "Nothing to rename")
	end

	local new, err = M.suggest(rt.plugin.ai_rename_cmd, name)
	if not new then
		return M.notify("error", tostring(err))
	end

	-- Hand the suggestion to Yazi's own `rename`, which prompts with it, renames the hovered file
	-- alone on submit, and asks before overwriting anything.
	ya.emit("rename", { name = new, hovered = true, cursor = "before_ext" })
end

---Split a configured command line into its program and leading arguments.
---@param cmd string
---@return string[]
function M.words(cmd)
	local words = {}
	for w in cmd:gmatch("%S+") do
		words[#words + 1] = w
	end
	return words
end

---Return the first non-blank line of `s`, trimmed, or `nil` when `s` has none.
---@param s string
---@return string?
function M.line(s)
	for line in s:gmatch("[^\r\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed ~= "" then
			return trimmed
		end
	end
end

---Ask the AI CLI to name a file called `name`, and return the single name it suggests.
---@param cmd string
---@param name string
---@return string?, Error?
function M.suggest(cmd, name)
	local args = M.words(cmd)
	local prog = table.remove(args, 1)
	if not prog then
		return nil, Err("`ai_rename_cmd` is empty, set it under `[plugin]` in your `yazi.toml`")
	end

	args[#args + 1] = string.format(PROMPT, name)

	local child, err = Command(prog):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()
	if not child then
		return nil, Err("Failed to start `%s`, error: %s", prog, err)
	end

	local output, err = child:wait_with_output()
	if not output then
		return nil, Err("Cannot read `%s` output, error: %s", prog, err)
	elseif not output.status.success then
		local stderr = M.clamp(output.stderr, STDERR_MAX, " ...")
		return nil, Err("`%s` exited with code %s: %s", prog, output.status.code, stderr)
	end

	local new = M.line(output.stdout)
	if not new then
		return nil, Err("`%s` suggested no name", prog)
	elseif #new > NAME_MAX then
		return nil, Err("`%s` suggested a name longer than %d bytes", prog, NAME_MAX)
	elseif new == "." or new == ".." or new:find("[/\\]") then
		return nil, Err("`%s` suggested `%s`, which isn't a filename", prog, new)
	end
	return new, nil
end

---Clamp `s` to at most `max` bytes, cutting on a codepoint boundary and appending `marker` when anything was cut.
---@param s string
---@param max integer
---@param marker string
---@return string
function M.clamp(s, max, marker)
	if #s <= max then
		return s
	end

	local ok, start = pcall(utf8.offset, s, 0, max + 1)
	return s:sub(1, ok and start and start - 1 or max) .. marker
end

function M.notify(level, s) ya.notify { title = "AI rename", content = s, timeout = 5, level = level } end

return M
