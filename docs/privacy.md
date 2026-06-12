# Privacy

The statusline hook stores local metrics in SQLite.

Stored fields:

- Conversation/session id.
- Transcript path.
- Persisted AIC counters.
- AIC delta rows.
- Unix timestamps.

The hook reads `events.jsonl` to calculate turn duration. The hook stores timing and AIC counters only. The hook leaves prompt text, assistant responses, and tool outputs out of the metrics database.

The database stays on the local machine by default:

```text
~/.copilot/statusline-metrics.db
```

Use `COPILOT_STATUSLINE_DB` to place the database somewhere else.

Review the database with:

```bash
sqlite3 ~/.copilot/statusline-metrics.db '.schema'
```
