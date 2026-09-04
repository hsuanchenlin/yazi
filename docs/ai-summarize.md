# ai-summarize

`ai-summarize` is a preset plugin that runs an AI CLI of your choosing over the files you have
selected, and drops the Markdown it prints into a summary file that Yazi then reveals and previews.

It is always an explicit keystroke - nothing runs on hover, on preload, or in batch. The plugin only
reads the files you point it at; it never moves, renames, or deletes anything.

## Usage

Select one or more files (`<Space>`), or just hover one, and press `A`.

The plugin spawns your configured CLI with the target paths appended as arguments, writes the
Markdown from its stdout to `<runtime dir>/ai-summaries/<timestamp>.md`, and reveals that file so the
preview pane renders it. Press `H` to go back to where you were.

If the CLI can't be started, exits non-zero, or prints nothing, the plugin reports it as a
notification and leaves everything untouched. A summary is capped at 1 MiB; anything beyond that is
dropped with a note at the end of the file.

## Configuration

The command lives under `[plugin]` in your `yazi.toml`:

```toml
[plugin]
ai_summarize_cmd = "claude --print"
```

It defaults to `claude --print`. The string is split on whitespace into a program and its leading
arguments, then the target paths are appended - it is not run through a shell, so pipes,
redirections, and quoting have no effect here.

Every whitespace-separated word becomes its own argument, which means a multi-word prompt cannot be
passed inline: `"claude --print Summarize these files:"` reaches `claude` as four separate arguments,
not one prompt. Use the shipped wrapper below whenever you want a prompt, or anything else a shell
would normally do for you.

### Examples

```toml
# Claude Code, the default
ai_summarize_cmd = "claude --print"

# Any other CLI that reads paths as arguments and prints Markdown
ai_summarize_cmd = "gpt --model gpt-5 summarize"

# No AI at all - handy for checking the wiring, since `cat` just echoes the files back
ai_summarize_cmd = "cat"
```

### Wrapper script

This repo ships `scripts/ya-summarize`. It holds a fixed summarize instruction and passes the file
paths through as argv, so you never have to put a multi-word prompt in `yazi.toml`. Copy it to an
absolute path:

```sh
mkdir -p "$HOME/.local/bin"
cp scripts/ya-summarize "$HOME/.local/bin/ya-summarize"
chmod +x "$HOME/.local/bin/ya-summarize"
```

Then point the plugin at that path. Spell it out in full: `~` is not expanded, and each word in
`ai_summarize_cmd` is its own argument, so a leading `~` would be looked up as a program literally
named `~/.local/bin/ya-summarize`.

```toml
[plugin]
ai_summarize_cmd = "/Users/you/.local/bin/ya-summarize"
```

The script defaults to `claude --print`. Override the binary with `YA_SUMMARIZE_CLI` (a single
executable name or path, default `claude`) and extra flags with `YA_SUMMARIZE_ARGS` (default
`--print`).

## Remapping the key

`A` is the default. To use a different key, prepend your own binding in `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "c", "s" ]
run  = "plugin ai-summarize"
desc = "Summarize the selected files with an AI CLI"
```

Note that `A` is upstream Yazi's `bulk_create` key. Taking it over for `ai-summarize` moves
`bulk_create` aside; [`ai-rename`](ai-rename.md) then took `R`, so `bulk_create` now sits on `B`.
Nothing is lost, but the muscle memory changes.

## Privacy

No API keys ship with Yazi and no network request is made from Yazi itself - the plugin only spawns
the binary you configured. Whatever that binary does with your files is between you and it.
