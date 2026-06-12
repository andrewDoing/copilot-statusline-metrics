# AIC Metrics Query Skill

Goal: Help the user inspect Copilot CLI AIC usage captured by the statusline metrics database.

Success means:
- Return SQLite queries that read `~/.copilot/statusline-metrics.db` or `$COPILOT_STATUSLINE_DB`.
- Explain daily, weekly, monthly, conversation, and event-level AIC usage with concise commands.
- Include the view or table each query reads.

Stop when: The user has a command they can paste into a terminal or adapt in SQLite.

## Database

Use this database path by default:

```bash
sqlite3 ~/.copilot/statusline-metrics.db
```

Use this environment override when the user configured a custom path:

```bash
sqlite3 "$COPILOT_STATUSLINE_DB"
```

## Daily usage

Read the daily rollup view:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT day, printf('%.4f', aic) AS aic, conversations
   FROM aic_daily
   ORDER BY day DESC;"
```

## Weekly usage

Read the weekly rollup view:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT week, printf('%.4f', aic) AS aic, conversations
   FROM aic_weekly
   ORDER BY week DESC;"
```

## Monthly usage

Read the monthly rollup view:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT month, printf('%.4f', aic) AS aic, conversations
   FROM aic_monthly
   ORDER BY month DESC;"
```

## Conversation totals

Read the conversation table:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT conversation_id,
          printf('%.4f', persisted_aic_nano / 1000000000.0) AS aic,
          datetime(updated_at, 'unixepoch', 'localtime') AS updated_at
   FROM conversations
   ORDER BY updated_at DESC;"
```

## Recent AIC deltas

Read the event table:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT datetime(created_at, 'unixepoch', 'localtime') AS observed_at,
          conversation_id,
          printf('%.4f', delta_aic_nano / 1000000000.0) AS delta_aic
   FROM aic_events
   ORDER BY created_at DESC
   LIMIT 50;"
```

## Custom ranges

Filter event rows with SQLite local dates:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT date(created_at, 'unixepoch', 'localtime') AS day,
          printf('%.4f', SUM(delta_aic_nano) / 1000000000.0) AS aic
   FROM aic_events
   WHERE created_at >= strftime('%s', 'now', '-30 days')
   GROUP BY day
   ORDER BY day DESC;"
```

## Schema check

List the installed schema:

```bash
sqlite3 ~/.copilot/statusline-metrics.db \
  "SELECT name, type
   FROM sqlite_master
   WHERE name IN ('schema_meta','conversations','aic_events','aic_daily','aic_weekly','aic_monthly')
   ORDER BY name;"
```
