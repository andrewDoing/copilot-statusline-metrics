#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
install_bin="$copilot_home/bin"
hook_path="$install_bin/copilot-statusline-metrics"
settings_path="$copilot_home/settings.json"
skill_target="$copilot_home/skills/aic-metrics"
extension_target="$copilot_home/extensions/copilot-statusline-metrics"

for dependency in jq sqlite3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Install dependency first: $dependency" >&2
    exit 1
  fi
done

mkdir -p "$install_bin" "$copilot_home/skills" "$copilot_home/extensions"

cp "$repo_root/bin/copilot-statusline-metrics" "$hook_path"
chmod +x "$hook_path"

rm -rf "$skill_target"
cp -R "$repo_root/skills/aic-metrics" "$skill_target"

rm -rf "$extension_target"
mkdir -p "$extension_target"
cp "$repo_root/.github/extensions/copilot-statusline-metrics/extension.mjs" "$extension_target/extension.mjs"

if [[ ! -f "$settings_path" ]]; then
  printf '{}\n' >"$settings_path"
fi

tmp_settings="$(mktemp)"
jq --arg command "$hook_path" '
  .statusLine = {
    type: "command",
    command: $command,
    padding: 1
  }
' "$settings_path" >"$tmp_settings"
mv "$tmp_settings" "$settings_path"

echo "Installed Copilot statusline metrics."
echo "Hook: $hook_path"
echo "Database: ${COPILOT_STATUSLINE_DB:-$copilot_home/statusline-metrics.db}"
echo "Restart Copilot CLI or run /restart to reload settings and extensions."
