#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo_root/bin/copilot-statusline-metrics"
failures=0

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label: expected to contain '$needle', got '$haystack'"
  fi
}

assert_equals() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label: expected '$expected', got '$actual'"
  fi
}

for dependency in jq sqlite3 node; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    fail "dependency $dependency is available"
    exit 1
  fi
done

bash -n "$hook"
bash -n "$repo_root/install.sh"
bash -n "$repo_root/uninstall.sh"
node --check "$repo_root/.github/extensions/copilot-statusline-metrics/extension.mjs" >/dev/null
pass "syntax checks"

if grep -q 'extensions", "copilot-statusline-metrics"' "$repo_root/.github/extensions/copilot-statusline-metrics/extension.mjs"; then
  pass "extension uninstall removes extension directory"
else
  fail "extension uninstall removes extension directory"
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

events_dir="$workdir/session"
mkdir -p "$events_dir"
cat >"$events_dir/events.jsonl" <<'JSONL'
{"type":"user.message","timestamp":"2026-06-12T18:00:00Z"}
{"type":"assistant.turn_start","timestamp":"2026-06-12T18:00:00Z"}
{"type":"assistant.message","timestamp":"2026-06-12T18:00:04Z"}
{"type":"assistant.turn_end","timestamp":"2026-06-12T18:00:08Z"}
JSONL

db="$workdir/statusline-metrics.db"
payload() {
  local session_id="$1"
  local aic="$2"
  printf '{"session_id":"%s","transcript_path":"%s","ai_used":{"total_nano_aiu":%s}}' "$session_id" "$events_dir" "$aic"
}

output="$(payload test-convo 66000000000 | COPILOT_STATUSLINE_DB="$db" "$hook")"
assert_contains "completed turn label" "$output" "Timer Last turn 00:08"
assert_contains "total active label" "$output" "Total active 00:08"
assert_contains "conversation AIC label" "$output" "AIC convo 66"

payload test-convo 66000000000 | COPILOT_STATUSLINE_DB="$db" "$hook" >/dev/null
payload test-convo 0 | COPILOT_STATUSLINE_DB="$db" "$hook" >/dev/null
payload test-convo 0 | COPILOT_STATUSLINE_DB="$db" "$hook" >/dev/null
output="$(payload test-convo 2000000000 | COPILOT_STATUSLINE_DB="$db" "$hook")"
assert_contains "restart reset accumulates delta" "$output" "AIC convo 68"

event_summary="$(sqlite3 "$db" 'SELECT COUNT(*), SUM(delta_aic_nano), MAX(observed_aic_nano) FROM aic_events;')"
assert_equals "event history deduplicates renders" "$event_summary" "2|68000000000|66000000000"

daily="$(sqlite3 "$db" 'SELECT day, aic, conversations FROM aic_daily;')"
assert_equals "daily rollup view" "$daily" "2026-06-12|68.0|1"

schema_version="$(sqlite3 "$db" "SELECT value FROM schema_meta WHERE key = 'schema_version';")"
assert_equals "schema version marker" "$schema_version" "1"

active_dir="$workdir/active-session"
mkdir -p "$active_dir"
now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat >"$active_dir/events.jsonl" <<JSONL
{"type":"user.message","timestamp":"$now_iso"}
{"type":"assistant.turn_start","timestamp":"$now_iso"}
JSONL
active_output="$(printf '{"session_id":"active-convo","transcript_path":"%s","ai_used":{"total_nano_aiu":1000000000}}' "$active_dir" | COPILOT_STATUSLINE_DB="$db" "$hook")"
assert_contains "active turn label" "$active_output" "Timer Turn"

install_home="$workdir/home"
export HOME="$install_home"
export COPILOT_HOME="$install_home/.copilot"
mkdir -p "$COPILOT_HOME"
printf '{"theme":"auto"}\n' >"$COPILOT_HOME/settings.json"
"$repo_root/install.sh" >/dev/null

installed_hook="$(jq -r '.statusLine.command' "$COPILOT_HOME/settings.json")"
assert_equals "installer writes statusLine command" "$installed_hook" "$COPILOT_HOME/bin/copilot-statusline-metrics"
[[ -x "$installed_hook" ]] && pass "installer copies executable hook" || fail "installer copies executable hook"
[[ -f "$COPILOT_HOME/skills/aic-metrics/SKILL.md" ]] && pass "installer copies skill" || fail "installer copies skill"
[[ -f "$COPILOT_HOME/extensions/copilot-statusline-metrics/extension.mjs" ]] && pass "installer copies extension" || fail "installer copies extension"

"$repo_root/uninstall.sh" >/dev/null
status_line_after_uninstall="$(jq -r '.statusLine // empty' "$COPILOT_HOME/settings.json")"
assert_equals "uninstaller removes matching statusLine" "$status_line_after_uninstall" ""

if ((failures > 0)); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf 'All tests passed\n'
