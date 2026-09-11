# Releasing the fork

Fork releases are tagged `v<upstream version>.<fork patch>-ai` (for example `v26.9.2-ai`) on top of
an upstream release, without bumping the Cargo workspace version - that keeps upstream merges clean.

## How the displayed version is resolved

`yazi --version` is served by the `yazi-version` crate. Its build script picks, in order:

1. `YAZI_VERSION` from the environment, when set (useful for builds from a source tarball, where no
   git metadata exists);
2. an exact `git describe --tags --exact-match` at `HEAD`, with the leading `v` stripped, so any
   build checked out at a release tag reports that tag's version;
3. the Cargo workspace version, as upstream does.

Ordinary development and nightly builds are never on an exact tag, so they keep reporting the
workspace version, exactly like upstream. Upstream's own flow is unaffected too: upstream bumps the
workspace version before tagging, so the tag-derived version equals the workspace one.

## Cutting a release

1. Tag the merge: `git tag v26.9.3-ai <commit> && git push origin v26.9.3-ai`.
2. Build from a checkout at the tag; the binary reports the tag version automatically. To override
   explicitly (or when building without git metadata), export `YAZI_VERSION=26.9.3-ai`.
3. Verify with `yazi --version` before publishing the archive.
4. Point the `hsuanchenlin/tap` Homebrew formula at the new archive.
