use mlua::{AnyUserData, Lua, ObjectLike, Table, chunk};
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

fn skip(plugin: &Table, run: &str, skip: usize, height: usize, total: usize) -> usize {
	plugin
		.call_function("skip", (run, skip, height, total))
		.unwrap_or_else(|e| panic!("`skip` must handle `{run}`: {e}"))
}

fn position(plugin: &Table, skip: usize, height: usize, total: usize) -> Option<String> {
	plugin.call_function("position", (skip, height, total)).unwrap()
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

#[test]
fn viewer_scrolls_within_the_summary() {
	let (_lua, plugin) = ai_summarize();

	// A 10-line viewport over 25 lines can skip at most 15 of them.
	assert_eq!(skip(&plugin, "next", 0, 10, 25), 1);
	assert_eq!(skip(&plugin, "prev", 1, 10, 25), 0);
	assert_eq!(skip(&plugin, "prev", 0, 10, 25), 0, "scrolling up at the top must stay put");
	assert_eq!(skip(&plugin, "next", 15, 10, 25), 15, "scrolling down at the end must stay put");

	assert_eq!(skip(&plugin, "half_next", 0, 10, 25), 5);
	assert_eq!(skip(&plugin, "half_prev", 5, 10, 25), 0);
	assert_eq!(skip(&plugin, "page_next", 0, 10, 25), 10);
	assert_eq!(skip(&plugin, "page_next", 10, 10, 25), 15, "a page past the end must clamp");
	assert_eq!(skip(&plugin, "page_prev", 15, 10, 25), 5);

	assert_eq!(skip(&plugin, "bot", 0, 10, 25), 15);
	assert_eq!(skip(&plugin, "top", 15, 10, 25), 0);

	// A summary that fits never scrolls; a one-line viewport still steps a whole line at a time.
	for run in ["next", "half_next", "page_next", "bot"] {
		assert_eq!(skip(&plugin, run, 0, 10, 10), 0, "`{run}` must not scroll a summary that fits");
	}
	for run in ["next", "half_next", "page_next"] {
		assert_eq!(skip(&plugin, run, 0, 1, 3), 1, "`{run}` must not get stuck in a one-line viewport");
	}
}

#[test]
fn every_viewer_key_is_handled() {
	let (_lua, plugin) = ai_summarize();

	let keys: Table = plugin.get("keys").unwrap();
	let mut closes = 0;
	for key in keys.sequence_values::<Table>() {
		let key = key.unwrap();
		let (on, run): (String, String) = (key.get("on").unwrap(), key.get("run").unwrap());
		if run == "close" {
			closes += 1;
		} else {
			skip(&plugin, &run, 0, 10, 25);
		}
		assert!(!on.is_empty(), "`{run}` must be bound to a key");
	}

	assert!(closes > 0, "the viewer must have a key that closes it");
}

#[test]
fn viewer_reports_its_position() {
	let (_lua, plugin) = ai_summarize();

	assert_eq!(position(&plugin, 0, 10, 10), None, "a summary that fits needs no position");
	assert_eq!(position(&plugin, 0, 10, 25).as_deref(), Some("Top"));
	assert_eq!(position(&plugin, 15, 10, 25).as_deref(), Some("Bot"));
	assert_eq!(position(&plugin, 5, 10, 25).as_deref(), Some("60%"));
}

#[test]
fn viewer_is_centered_and_readable() {
	let (lua, plugin) = ai_summarize();

	let area = |w: u16, h: u16| -> (u16, u16, u16, u16) {
		let plugin = &plugin;
		lua
			.load(chunk! {
				local r = $plugin.area(ui.Rect { x = 0, y = 0, w = $w, h = $h })
				return r.x, r.y, r.w, r.h
			})
			.call(())
			.unwrap()
	};

	assert_eq!(area(120, 36), (12, 4, 96, 28), "the viewer takes 80% of a normal terminal, centered");
	assert_eq!(area(300, 50), (100, 5, 100, 40), "the viewer never grows past 100 columns");
	assert_eq!(area(0, 0), (0, 0, 0, 0), "a degenerate terminal must not underflow");
}
