use mlua::{AnyUserData, Lua, ObjectLike, Table};
use yazi_binding::{Runtime, Scope};
use yazi_macro::plugin_preset as preset;

/// Loads the `ai-summarize` preset into the same slim Lua environment the plugin
/// runner builds for it in production.
fn ai_summarize() -> (Lua, Table) {
	let lua = Lua::new();
	lua.set_app_data(Runtime::new("ai-summarize", Scope::default()));
	yazi_plugin::slim_lua(&lua).unwrap();

	let plugin =
		lua.load(preset!("plugins/ai-summarize")).set_name("ai-summarize.lua").eval().unwrap();

	(lua, plugin)
}

#[tokio::test]
async fn missing_cli_is_reported_not_raised() {
	let (_lua, plugin) = ai_summarize();

	let (md, err): (Option<String>, AnyUserData) = plugin
		.call_function("summarize", ("yazi-no-such-ai-cli --print", ["/etc/hosts"]))
		.expect("`summarize` must report a missing CLI, not raise an error");

	assert_eq!(md, None);
	assert!(
		err.to_string().unwrap().contains("yazi-no-such-ai-cli"),
		"the error must name the CLI that couldn't be started"
	);
}
