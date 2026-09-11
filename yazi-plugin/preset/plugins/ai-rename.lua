local M = {}

local NAME_MAX = 255
local STDERR_MAX = 1024

local PROMPT = [[
Suggest a clearer filename for a file currently named %q.
Keep its extension. Reply with the new filename alone: one line, no directory, no quotes, no explanation.
]]

local hovered = ya.sync(function()
	local h = cx.active.current.hovered
	if h then
		return tostring(h.url), h.name
	end
end)

---Prompt to rename `url`, but only while it is still the hovered file.
---
---The check and the emit share one sync block, so the main thread cannot process a keystroke - and
---move the hover elsewhere - between them.
---@param url string
---@param name string
---@return boolean
local rename = ya.sync(function(_, url, name)
	local h = cx.active.current.hovered
	if not h or tostring(h.url) ~= url then
		return false
	end

	-- Hand the suggestion to Yazi's own `rename`, which prompts with it, renames the hovered file
	-- alone on submit, and asks before overwriting anything.
	ya.emit("rename", { name = name, hovered = true, cursor = "before_ext" })
	return true
end)

---Claim the plugin for one run, showing `text` on the status bar until `finish`.
---
---A second `R` while a name is still being suggested is refused rather than billed twice.
---@param text string
---@return boolean
local begin = ya.sync(function(self, text)
	if self._busy then
		return false
	end

	self._busy = text
	ui.render()
	return true
end)

local finish = ya.sync(function(self)
	self._busy = nil
	ui.render()
end)

function M:setup()
	Status:children_add(function(status) return self:status(status) end, 600, Status.RIGHT)
end

function M:entry()
	local url, name = hovered()
	if not url then
		return M.notify("warn", "Nothing to rename")
	elseif not begin("Suggesting a name…") then
		return M.notify("warn", "A name is still being suggested, wait for it to arrive first")
	end
	M.notify("info", string.format("Suggesting a new name for `%s`…", name))

	local new, err = M.suggest(rt.plugin.ai_rename_cmd, name)
	finish()
	if not new then
		return M.notify("error", tostring(err))
	end

	if not rename(url, new) then
		M.notify("warn", string.format("The hover left `%s` while it was being named, nothing renamed", name))
	end
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

---Take the name `prog` suggested out of its `stdout`, refusing anything that cannot name a file.
---@param prog string
---@param stdout string
---@return string?, Error?
function M.parse(prog, stdout)
	local new = M.line(stdout)
	if not new then
		return nil, Err("`%s` suggested no name", prog)
	elseif #new > NAME_MAX then
		return nil, Err("`%s` suggested a name longer than %d bytes", prog, NAME_MAX)
	elseif new == "." or new == ".." or new:find("[/\\]") then
		return nil, Err("`%s` suggested `%s`, which isn't a filename", prog, new)
	end
	return new, nil
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
	return M.parse(prog, output.stdout)
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

---The status bar segment: what `R` does, or what it is busy doing when `status` has room for that beside the task gauge.
---@param status Status
---@return Line|string
function M:status(status)
	if not self._busy then
		return ui.Line { ui.Span("R"):style(th.which.cand), ui.Span(" Rename  "):style(th.which.desc) }
	elseif status:cramped() then
		return ""
	else
		return ui.Line { ui.Span(self._busy .. "  "):style(th.which.desc) }
	end
end

function M.notify(level, s) ya.notify { title = "AI rename", content = s, timeout = 5, level = level } end

return M
