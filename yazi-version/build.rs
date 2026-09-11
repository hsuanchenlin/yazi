use std::{env, error::Error, process::Command};

use vergen_gitcl::{Build, Emitter, Gitcl, Rustc};

fn main() -> Result<(), Box<dyn Error>> {
	Emitter::default()
		.add_instructions(&Build::builder().build_date(true).build())?
		.add_instructions(
			&Rustc::builder().commit_date(true).commit_hash(true).host_triple(true).semver(true).build(),
		)?
		.emit()?;

	if env::var_os("YAZI_NO_GITCL").is_none() {
		Emitter::default()
			.default_on_error()
			.add_instructions(&Gitcl::builder().sha(true).build())?
			.emit()?;
	} else {
		println!("cargo:rustc-env=VERGEN_GIT_SHA=no-gitcl");
	}

	version();
	Ok(())
}

// Fork releases are tagged `v<version>-ai` without bumping Cargo versions, so
// an explicit `YAZI_VERSION` or an exact git tag overrides the workspace
// version baked into the binary.
fn version() {
	println!("cargo:rerun-if-env-changed=YAZI_VERSION");

	let version = env::var("YAZI_VERSION").ok().filter(|s| !s.is_empty()).or_else(exact_tag);
	if let Some(v) = version {
		println!("cargo:rustc-env=YAZI_VERSION={}", v.strip_prefix('v').unwrap_or(&v));
	}
}

fn exact_tag() -> Option<String> {
	if env::var_os("YAZI_NO_GITCL").is_some() {
		return None;
	}

	let out = Command::new("git").args(["describe", "--tags", "--exact-match"]).output().ok()?;
	out
		.status
		.success()
		.then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
		.filter(|s| !s.is_empty())
}
