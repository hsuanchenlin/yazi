# ai-rename

`ai-rename` is a preset plugin that asks an AI CLI of your choosing for a better name for the file
you are hovering, then hands that name to Yazi's own rename prompt so you can edit it, accept it, or
throw it away.

It is always an explicit keystroke - nothing runs on hover, on preload, or in batch. One invocation
touches at most one file, and only after you press `<Enter>` at the prompt. The plugin never renames
in bulk, never moves a file to another directory, and never deletes anything.

## Usage

Hover a file and press `R`.

The plugin sends the filename - the basename alone, never the path - to your configured CLI, takes
the first non-blank line of its stdout as the suggestion, and opens Yazi's rename prompt pre-filled
with it. From there it is the ordinary rename you already know:

- `<Enter>` renames, asking first if a file of that name already exists.
- `<Esc>` cancels, and nothing changes.

Selected files are ignored: `ai-rename` always works on the hovered file, so it can never turn into a
bulk rename. Use `r` for that.

If the CLI can't be started, exits non-zero, or suggests nothing usable, the plugin reports it as a
notification and no prompt opens. A suggestion is refused outright when it is longer than 255 bytes,
or when it is `.`, `..`, or contains a `/` or `\` - a new name is a name, not a path.

## Configuration

The command lives under `[plugin]` in your `yazi.toml`:

```toml
[plugin]
ai_rename_cmd = "claude --print"
```

It defaults to `claude --print`. The string is split on whitespace into a program and its leading
arguments, then one final argument is appended: a short prompt naming the file and asking for a
single filename back. It is not run through a shell, so pipes, redirections, and quoting have no
effect here.

Every whitespace-separated word becomes its own argument, which means a multi-word flag value cannot
be passed inline: `"claude --print --system You are terse"` reaches `claude` as six separate
arguments. Use the wrapper script below whenever you want a shell to do that for you.

### Examples

```toml
# Claude Code, the default
ai_rename_cmd = "claude --print"

# Any other CLI that reads a prompt as its last argument and prints a filename
ai_rename_cmd = "gpt --model gpt-5"

# No AI at all - handy for checking the wiring, since `echo` just prints the prompt back
ai_rename_cmd = "echo"
```

A wrapper script when you need shell features:

```sh
#!/bin/sh
# ~/.local/bin/ya-rename
exec claude --print --system-prompt 'Answer with a filename and nothing else.' "$1"
```

```toml
[plugin]
ai_rename_cmd = "/home/you/.local/bin/ya-rename"
```

Spell that path out in full: since the command is not run through a shell, a leading `~` is not
expanded and would be looked up as a program literally named `~/.local/bin/ya-rename`.

`ai_rename_cmd` is separate from [`ai_summarize_cmd`](ai-summarize.md), so the two plugins can use
different tools.

## Remapping the key

`R` is the default. To use a different key, prepend your own binding in `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "c", "r" ]
run  = "plugin ai-rename"
desc = "Rename the hovered file with a name an AI CLI suggests"
```

Note that `R` was this fork's `bulk_create` key, which upstream Yazi binds to `A`. Taking `A` for
`ai-summarize` moved `bulk_create` to `R`; taking `R` for `ai-rename` moves it on to `B`, which is
otherwise unbound. Nothing is lost, but the muscle memory changes.

## Privacy

No API keys ship with Yazi and no network request is made from Yazi itself - the plugin only spawns
the binary you configured, and tells it a single filename. Whatever that binary does with that name
is between you and it.
