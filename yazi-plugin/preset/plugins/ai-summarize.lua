local M = {}

local STDOUT_MAX = 1024 * 1024
local STDERR_MAX = 1024

-- What the viewer answers to: `close`, or a `skip` movement.
M.keys = {
	{ on = "q", run = "close" },
	{ on = "<Esc>", run = "close" },
	{ on = "<C-[>", run = "close" },
	{ on = "<C-c>", run = "close" },

	{ on = "k", run = "prev" },
	{ on = "j", run = "next" },
	{ on = "<Up>", run = "prev" },
	{ on = "<Down>", run = "next" },

	{ on = "<C-u>", run = "half_prev" },
	{ on = "<C-d>", run = "half_next" },
	{ on = "<PageUp>", run = "page_prev" },
	{ on = "<PageDown>", run = "page_next" },

	{ on = "g", run = "top" },
	{ on = "G", run = "bot" },
}

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

---Claim the plugin for one run, showing `text` on the status bar until `finish`.
---
---A second `A` while a summary is still generating is refused rather than billed twice.
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

local open = ya.sync(function(self, text)
	self._text, self._skip = text, 0
	self._child = Modal:children_add(self, 10)
	ui.render()
end)

local close = ya.sync(function(self)
	Modal:children_remove(self._child)
	self._text, self._child = nil, nil
	ui.render()
end)

local seek = ya.sync(function(self, run)
	self._skip = M.skip(run, self._skip, self._height or 0, self._total or 0)
	ui.render()
end)

---Hand `text` to the viewer on the main thread, so the summary task ends as soon as the summary is ready
---instead of lingering in the task list for as long as the viewer stays open.
---@param text string
local show = ya.sync(function(self, text)
	ya.async(function() self.view(text) end)
end)

function M:setup()
	Status:children_add(function(status) return self:status(status) end, 500, Status.RIGHT)
end

function M:entry()
	local paths = targets()
	if #paths == 0 then
		return M.notify("warn", "Nothing to summarize")
	end

	local text = string.format("Summarizing %d file%s…", #paths, #paths == 1 and "" or "s")
	if not begin(text) then
		return M.notify("warn", "A summary is still being generated, wait for it to finish first")
	end
	M.notify("info", text)

	local md, err = M.summarize(rt.plugin.ai_summarize_cmd, paths)
	finish()
	if not md then
		return M.notify("error", tostring(err))
	end

	local url, err = M.save(md, paths)
	if not url then
		M.notify("warn", tostring(err))
	end

	show(M.render(md, paths))
end

---Show `text` in a modal viewer over the current tab, and return once the user closes it.
---@param text string
function M.view(text)
	open(text)
	while true do
		local cand = M.keys[ya.which { cands = M.keys, silent = true }]
		if cand and cand.run == "close" then
			break
		elseif cand then
			seek(cand.run)
		end
	end
	close()
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

---Where the viewer lands after `run`, showing `height` of `total` lines from `skip` onwards.
---@param run string
---@param skip integer
---@param height integer
---@param total integer
---@return integer
function M.skip(run, skip, height, total)
	local half, page = math.max(1, height // 2), math.max(1, height)
	local step = ({
		prev = -1,
		next = 1,
		half_prev = -half,
		half_next = half,
		page_prev = -page,
		page_next = page,
		top = -total,
		bot = total,
	})[run]
	return ya.clamp(0, skip + step, math.max(0, total - height))
end

---How far the viewer has scrolled, in the words of the status bar: `Top`, `Bot`, or a percentage.
---@param skip integer
---@param height integer
---@param total integer
---@return string?
function M.position(skip, height, total)
	if total <= height then
		return nil
	elseif skip == 0 then
		return "Top"
	elseif skip + height >= total then
		return "Bot"
	else
		return string.format("%d%%", (skip + height) * 100 // total)
	end
end

---The status bar segment: what `A` does, or what it is busy doing when `status` has room for that beside the task gauge.
---@param status Status
---@return Line|string
function M:status(status)
	if not self._busy then
		return ui.Line { ui.Span("A"):style(th.which.cand), ui.Span(" Summarize  "):style(th.which.desc) }
	elseif status:cramped() then
		return ""
	else
		return ui.Line { ui.Span(self._busy .. "  "):style(th.which.desc) }
	end
end

---Center a reading pane no wider than 100 columns on `area`.
---@param area Rect
---@return Rect
function M.area(area)
	local w, h = math.min(100, area.w * 4 // 5), area.h * 4 // 5
	return ui.Rect { x = area.x + (area.w - w) // 2, y = area.y + (area.h - h) // 2, w = w, h = h }
end

function M:new(area)
	self._area = M.area(area)
	return self
end

function M:reflow() return { self } end

function M:redraw()
	local inner = self._area:pad(ui.Pad(1, 2, 1, 2))
	local lines =
		ui.lines(self._text, { wrap = ui.Wrap.YES, width = inner.w, tab_size = rt.preview.tab_size, ansi = false })

	self._height, self._total = inner.h, #lines
	self._skip = math.min(self._skip, math.max(0, #lines - inner.h))

	local border = ui.Border(ui.Edge.ALL)
		:area(self._area)
		:style(th.spot.border)
		:title(ui.Line(" AI summary "):align(ui.Align.CENTER):style(th.spot.title))
		:title(
			ui.Line {
				ui.Span(" j/k"):style(th.which.cand),
				ui.Span(" scroll  "):style(th.which.desc),
				ui.Span("q"):style(th.which.cand),
				ui.Span(" close "):style(th.which.desc),
			},
			ui.Edge.BOTTOM
		)

	local position = M.position(self._skip, inner.h, #lines)
	if position then
		border:title(ui.Line(" " .. position .. " "):align(ui.Align.RIGHT):style(th.spot.title), ui.Edge.BOTTOM)
	end

	return {
		ui.Clear(self._area),
		border,
		ui.Text(table.move(lines, self._skip + 1, self._skip + inner.h, 1, {})):area(inner),
	}
end

function M.notify(level, s) ya.notify { title = "AI summarize", content = s, timeout = 5, level = level } end

return M
