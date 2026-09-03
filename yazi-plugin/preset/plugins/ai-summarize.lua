local M = {}

local STDOUT_MAX = 1024 * 1024
local STDERR_MAX = 1024

local targets = ya.sync(function()
	local paths = {}
	for _, f in pairs(cx.active.selected) do
		paths[#paths + 1] = tostring(f.path)
	end

	local h = cx.active.current.hovered
	if #paths == 0 and h then
		paths[1] = tostring(h.path)
	end
	return paths
end)

function M:entry()
	local paths = targets()
	if #paths == 0 then
		return M.notify("warn", "Nothing to summarize")
	end

	local md, err = M.summarize(rt.plugin.ai_summarize_cmd, paths)
	if not md then
		return M.notify("error", tostring(err))
	end

	local url, err = M.save(md, paths)
	if not url then
		return M.notify("error", tostring(err))
	end

	ya.emit("reveal", { url, raw = true })
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

---Clamp `s` to at most `max` bytes, appending `marker` when anything was cut.
---@param s string
---@param max integer
---@param marker string
---@return string
function M.clamp(s, max, marker) return #s <= max and s or s:sub(1, max) .. marker end

---Run the AI CLI over `paths`, and return whatever Markdown it writes to stdout.
---@param cmd string
---@param paths string[]
---@return string?, Error?
function M.summarize(cmd, paths)
	local args = M.words(cmd)
	local prog = table.remove(args, 1)
	if not prog then
		return nil, Err("`ai_summarize_cmd` is empty, set it under `[plugin]` in your `yazi.toml`")
	end

	for _, p in ipairs(paths) do
		args[#args + 1] = p
	end

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
	elseif output.stdout == "" then
		return nil, Err("`%s` produced an empty summary", prog)
	end
	return M.clamp(output.stdout, STDOUT_MAX, "\n\n> Truncated here: the summary exceeded 1 MiB."), nil
end

---Write the summary to its own file under Yazi's runtime directory, leaving the summarized files untouched.
---@param md string
---@param paths string[]
---@return Url?, Error?
function M.save(md, paths)
	local dir = Url(rt.path.runtime_dir):join("ai-summaries")
	local ok, err = fs.create("dir_all", dir)
	if not ok then
		return nil, Err("Failed to create '%s', error: %s", dir, err)
	end

	local url, err = fs.unique("file", dir:join(os.date("%Y-%m-%d %H-%M-%S") .. ".md"))
	if not url then
		return nil, Err("Failed to determine a summary file, error: %s", err)
	end

	local ok, err = fs.write(url, M.render(md, paths))
	if not ok then
		return nil, Err("Failed to write '%s', error: %s", url, err)
	end
	return url, nil
end

---@param md string
---@param paths string[]
---@return string
function M.render(md, paths)
	local lines = { "# AI summary", "" }
	for _, p in ipairs(paths) do
		lines[#lines + 1] = string.format("- `%s`", p)
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = md
	return table.concat(lines, "\n")
end

function M.notify(level, s) ya.notify { title = "AI summarize", content = s, timeout = 5, level = level } end

return M
