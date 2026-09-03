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
notification and leaves everything untouched.

## Configuration

The command lives under `[plugin]` in your `yazi.toml`:

```toml
[plugin]
ai_summarize_cmd = "claude --print"
```

It defaults to `claude --print`. The string is split on whitespace into a program and its leading
arguments, then the target paths are appended - it is not run through a shell, so pipes,
redirections, and quoting have no effect here. For anything more elaborate, point it at a wrapper
script of your own.

### Examples

```toml
# Claude Code, the default
ai_summarize_cmd = "claude --print"

# A prompt in front of the paths
ai_summarize_cmd = "claude --print Summarize each of these files in a few bullets:"

# Any other CLI that reads paths as arguments and prints Markdown
ai_summarize_cmd = "gpt --model gpt-5 summarize"

# No AI at all - handy for checking the wiring, since `cat` just echoes the files back
ai_summarize_cmd = "cat"
```

A wrapper script when you need shell features:

```sh
#!/bin/sh
# ~/.local/bin/ya-summarize
exec claude --print "Summarize these files for a code reviewer: $*"
```

```toml
[plugin]
ai_summarize_cmd = "/home/you/.local/bin/ya-summarize"
```

Spell that path out in full: since the command is not run through a shell, a leading `~` is not
expanded and would be looked up as a program literally named `~/.local/bin/ya-summarize`.

## Remapping the key

`A` is the default. To use a different key, prepend your own binding in `keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = [ "c", "s" ]
run  = "plugin ai-summarize"
desc = "Summarize the selected files with an AI CLI"
```

Note that `A` is upstream Yazi's `bulk_create` key. Taking it over for `ai-summarize` moves
`bulk_create` to `R`, which is otherwise unbound; nothing is lost, but the muscle memory changes.

## Privacy

No API keys ship with Yazi and no network request is made from Yazi itself - the plugin only spawns
the binary you configured. Whatever that binary does with your files is between you and it.
