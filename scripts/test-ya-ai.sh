#!/bin/sh
# Tiny tests for scripts/ya-summarize and scripts/ya-rename.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
summarize=$root/ya-summarize
rename=$root/ya-rename

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

ok() {
	printf 'ok - %s\n' "$1"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT INT HUP TERM

# --- missing CLI ---

status=0
err=$(YA_SUMMARIZE_CLI=yazi-no-such-ai-cli "$summarize" /etc/hosts 2>&1 >/dev/null) || status=$?
[ "$status" -ne 0 ] || fail "ya-summarize missing CLI should exit non-zero"
printf '%s\n' "$err" | grep -q 'yazi-no-such-ai-cli' || fail "ya-summarize missing CLI should name the binary on stderr"
ok "ya-summarize missing CLI"

status=0
err=$(YA_RENAME_CLI=yazi-no-such-ai-cli "$rename" notes.txt 2>&1 >/dev/null) || status=$?
[ "$status" -ne 0 ] || fail "ya-rename missing CLI should exit non-zero"
printf '%s\n' "$err" | grep -q 'yazi-no-such-ai-cli' || fail "ya-rename missing CLI should name the binary on stderr"
ok "ya-rename missing CLI"

# --- fake CLI ---

fake=$tmpdir/fake-cli
cat >"$fake" <<'EOF'
#!/bin/sh
for a in "$@"; do
	printf '%s\n' "$a"
done >"$YA_FAKE_ARGV"
if [ "${YA_FAKE_MODE:-}" = rename ]; then
	printf '%s\n' "" "  better-name.md  " "ignored"
	exit 0
fi
printf '%s\n' "# Known summary"
EOF
chmod +x "$fake"

file=$tmpdir/my\ file.txt
printf 'hello\n' >"$file"
argv=$tmpdir/summarize.argv
out=$(YA_SUMMARIZE_CLI=$fake YA_SUMMARIZE_ARGS= YA_FAKE_ARGV=$argv "$summarize" "$file")
[ "$out" = "# Known summary" ] || fail "ya-summarize stdout: $out"
grep -qx "$file" "$argv" || fail "ya-summarize should pass the file path as one argv entry"
ok "ya-summarize fake CLI"

argv=$tmpdir/summarize-print.argv
YA_SUMMARIZE_CLI=$fake YA_FAKE_ARGV=$argv "$summarize" "$file" >/dev/null
first=$(sed -n '1p' "$argv")
[ "$first" = "--print" ] || fail "ya-summarize should default YA_SUMMARIZE_ARGS to --print, got: $first"
ok "ya-summarize default --print"

# A path that would be disastrous if interpolated into a shell.
evil=$tmpdir/evil\;echo\ pwned
printf 'x\n' >"$evil"
argv=$tmpdir/summarize-evil.argv
YA_SUMMARIZE_CLI=$fake YA_SUMMARIZE_ARGS= YA_FAKE_ARGV=$argv "$summarize" "$evil" >/dev/null
grep -qx "$evil" "$argv" || fail "ya-summarize should pass a metacharacter path as one argv entry"
ok "ya-summarize argv-safe path"

argv=$tmpdir/rename.argv
out=$(YA_RENAME_CLI=$fake YA_RENAME_ARGS= YA_FAKE_MODE=rename YA_FAKE_ARGV=$argv "$rename" "notes.txt")
[ "$out" = "better-name.md" ] || fail "ya-rename stdout: $out"
grep -qx "notes.txt" "$argv" || fail "ya-rename should pass the filename as one argv entry"
ok "ya-rename fake CLI"

printf 'all tests passed\n'
