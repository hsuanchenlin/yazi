use mlua::{AnyUserData, Lua, ObjectLike, Table};
use yazi_binding::{Runtime, Scope};
use yazi_macro::plugin_preset as preset;

/// Loads the `ai-rename` preset into the same slim Lua environment the plugin
/// runner builds for it in production.
fn ai_rename() -> (Lua, Table) {
	let lua = Lua::new();
	lua.set_app_data(Runtime::new("ai-rename", Scope::default()));
	yazi_plugin::slim_lua(&lua).unwrap();

	let plugin = lua.load(preset!("plugins/ai-rename")).set_name("ai-rename.lua").eval().unwrap();

	(lua, plugin)
}

fn parse(plugin: &Table, stdout: &str) -> (Option<String>, AnyUserData) {
	plugin
		.call_function("parse", ("cli", stdout))
		.expect("`parse` must report a rejected suggestion, not raise an error")
}

#[tokio::test]
async fn missing_cli_is_reported_not_raised() {
	let (_lua, plugin) = ai_rename();

	let (name, err): (Option<String>, AnyUserData) = plugin
		.call_function("suggest", ("yazi-no-such-ai-cli --print", "notes.txt"))
		.expect("`suggest` must report a missing CLI, not raise an error");

	assert_eq!(name, None);
	assert!(
		err.to_string().unwrap().contains("yazi-no-such-ai-cli"),
		"the error must name the CLI that couldn't be started"
	);
}

#[test]
fn blank_suggestion_is_rejected() {
	let (_lua, plugin) = ai_rename();

	for stdout in ["", " \t ", "\n", "\n\n", "  \n\t\n  "] {
		let (name, err) = parse(&plugin, stdout);
		assert_eq!(name, None, "{stdout:?} suggested a name where it printed nothing usable");
		assert!(
			err.to_string().unwrap().contains("suggested no name"),
			"the error must say {stdout:?} suggested nothing to rename to"
		);
	}
}

#[test]
fn path_shaped_suggestion_is_rejected() {
	let (_lua, plugin) = ai_rename();

	for stdout in [".", "..", "../etc/", "foo/bar", r"foo\bar"] {
		let (name, err) = parse(&plugin, stdout);
		assert_eq!(name, None, "{stdout:?} must never be renamed to");
		assert!(
			err.to_string().unwrap().contains("isn't a filename"),
			"the error must say {stdout:?} wasn't a filename"
		);
	}
}

#[cfg(unix)]
#[tokio::test]
async fn blank_cli_stdout_is_rejected() {
	let (_lua, plugin) = ai_rename();

	// `true` succeeds printing nothing at all; the `printf` prints a lone newline and nothing else.
	for cmd in ["true", "printf \\n%.0s"] {
		let (name, err): (Option<String>, AnyUserData) = plugin
			.call_async_function("suggest", (cmd, "notes.txt"))
			.await
			.expect("`suggest` must report a blank suggestion, not raise an error");

		assert_eq!(name, None, "`{cmd}` suggested a name where it printed nothing usable");
		assert!(
			err.to_string().unwrap().contains("suggested no name"),
			"the error must say `{cmd}` suggested nothing to rename to"
		);
	}
}

#[cfg(unix)]
#[tokio::test]
async fn path_shaped_cli_stdout_is_rejected() {
	let (_lua, plugin) = ai_rename();

	// The `printf` prints `../etc/` and nothing else, standing in for a CLI that answers with a path.
	let (name, err): (Option<String>, AnyUserData) = plugin
		.call_async_function("suggest", ("printf ../etc/%.0s", "notes.txt"))
		.await
		.expect("`suggest` must report a path-shaped suggestion, not raise an error");

	assert_eq!(
		name, None,
		"a suggestion that escapes the current directory must never be renamed to"
	);
	assert!(
		err.to_string().unwrap().contains("isn't a filename"),
		"the error must say the suggestion wasn't a filename"
	);
}
