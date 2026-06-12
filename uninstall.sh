#!/usr/bin/env bash
set -euo pipefail

copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
hook_path="$copilot_home/bin/copilot-statusline-metrics"
settings_path="$copilot_home/settings.json"

if command -v jq >/dev/null 2>&1 && [[ -f "$settings_path" ]]; then
  tmp_settings="$(mktemp)"
  jq --arg command "$hook_path" '
    if .statusLine.command == $command then
      del(.statusLine)
    else
      .
    end
  ' "$settings_path" >"$tmp_settings"
  mv "$tmp_settings" "$settings_path"
fi

rm -f "$hook_path"
rm -rf "$copilot_home/skills/aic-metrics"
rm -rf "$copilot_home/extensions/copilot-statusline-metrics"

echo "Uninstalled Copilot statusline metrics."
echo "Metrics database retained at: ${COPILOT_STATUSLINE_DB:-$copilot_home/statusline-metrics.db}"
