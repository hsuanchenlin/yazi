use std::{env::{self, consts::{ARCH, OS}}, fmt::Write, sync::OnceLock};

// Workspace version, or the fork release version when built at an exact
// release tag or with `YAZI_VERSION` set (see `build.rs`).
const VERSION: &str = match option_env!("YAZI_VERSION") {
	Some(v) => v,
	None => env!("CARGO_PKG_VERSION"),
};

pub fn version() -> &'static str {
	static S: OnceLock<String> = OnceLock::new();
	S.get_or_init(|| format!("{VERSION} {}", env!("VERGEN_GIT_SHA")))
}

pub fn version_long() -> &'static str {
	static S: OnceLock<String> = OnceLock::new();
	S.get_or_init(|| format!("{VERSION} ({} {})", env!("VERGEN_GIT_SHA"), env!("VERGEN_BUILD_DATE")))
}

pub fn version_full() -> String {
	let mut s = String::new();

	writeln!(s, "    Version: {}", version_long()).ok();
	writeln!(s, "    Debug  : {}", cfg!(debug_assertions)).ok();
	#[rustfmt::skip]
	writeln!(s, "    Triple : {} ({OS}-{ARCH})", env!("VERGEN_RUSTC_HOST_TRIPLE")).ok();
	#[rustfmt::skip]
	writeln!(s, "    Rustc  : {} ({} {})", env!("VERGEN_RUSTC_SEMVER"), &env!("VERGEN_RUSTC_COMMIT_HASH")[..8], env!("VERGEN_RUSTC_COMMIT_DATE")).ok();

	s
}

pub fn has_dash_v() -> bool {
	env::args_os().skip(1).take_while(|arg| arg != "--").any(|arg| arg == "-V" || arg == "--version")
}

#[cfg(test)]
mod tests {
	#[test]
	fn version_reports_base_and_sha() {
		assert!(super::version().starts_with(super::VERSION));
		assert!(super::version().ends_with(env!("VERGEN_GIT_SHA")));
	}

	#[test]
	fn version_long_reports_build_date() {
		assert!(super::version_long().starts_with(super::VERSION));
		assert!(super::version_long().ends_with(&format!(
			"({} {})",
			env!("VERGEN_GIT_SHA"),
			env!("VERGEN_BUILD_DATE")
		)));
	}

	#[test]
	fn default_is_workspace_version() {
		// `YAZI_VERSION` is only set for fork release builds; `cargo test`
		// builds without it, so the base version is the workspace one.
		if option_env!("YAZI_VERSION").is_none() {
			assert_eq!(super::VERSION, env!("CARGO_PKG_VERSION"));
		}
	}
}
