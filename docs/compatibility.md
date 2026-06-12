# Compatibility and Troubleshooting

## Copilot CLI payload

The hook reads the JSON payload sent to `statusLine.command`.

Required fields:

- `transcript_path` or `transcriptPath`
- `ai_used.total_nano_aiu` or `ai_used.formatted`

The timer reads `events.jsonl` from the transcript directory and looks for:

- `user.message`
- `assistant.turn_start`
- `assistant.message`
- `assistant.turn_end`
- `tool.execution_start`
- `tool.execution_complete`
- `permission.*`

## Update cadence

Copilot CLI invokes the statusline command during UI refresh. The hook recalculates values on each invocation.

## Dependency check

Install dependencies:

```bash
command -v jq sqlite3 bash
```

macOS:

```bash
brew install jq sqlite
```

Debian or Ubuntu:

```bash
sudo apt-get install jq sqlite3
```

## Schema check

Run:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT key, value FROM schema_meta ORDER BY key;"
```

## Extension check

Inside Copilot CLI, run:

```text
/env
```

Use the extension tool:

```text
copilot_statusline_metrics_status
```
