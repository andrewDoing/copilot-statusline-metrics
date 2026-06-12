import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { joinSession } from "@github/copilot-sdk/extension";

const copilotHome = process.env.COPILOT_HOME || join(homedir(), ".copilot");
const hookPath = join(copilotHome, "bin", "copilot-statusline-metrics");
const dbPath = process.env.COPILOT_STATUSLINE_DB || join(copilotHome, "statusline-metrics.db");
const settingsPath = join(copilotHome, "settings.json");

function run(command, args, input) {
    return new Promise((resolve) => {
        const child = execFile(command, args, { timeout: 5000 }, (error, stdout, stderr) => {
            if (error) {
                resolve({ ok: false, stdout, stderr: stderr || error.message });
            } else {
                resolve({ ok: true, stdout, stderr });
            }
        });
        if (input) {
            child.stdin.end(input);
        }
    });
}

async function readSettings() {
    if (!existsSync(settingsPath)) {
        return {};
    }

    const text = await readFile(settingsPath, "utf8");
    return JSON.parse(text || "{}");
}

async function writeSettings(settings) {
    await mkdir(dirname(settingsPath), { recursive: true });
    await writeFile(settingsPath, `${JSON.stringify(settings, null, 2)}\n`);
}

function queryForPeriod(period, limit) {
    const safeLimit = Math.max(1, Math.min(Number(limit || 30), 365));
    if (period === "day") {
        return `SELECT day, printf('%.4f', aic) AS aic, conversations FROM aic_daily ORDER BY day DESC LIMIT ${safeLimit};`;
    }
    if (period === "week") {
        return `SELECT week, printf('%.4f', aic) AS aic, conversations FROM aic_weekly ORDER BY week DESC LIMIT ${safeLimit};`;
    }
    if (period === "month") {
        return `SELECT month, printf('%.4f', aic) AS aic, conversations FROM aic_monthly ORDER BY month DESC LIMIT ${safeLimit};`;
    }
    if (period === "conversation") {
        return `SELECT conversation_id, printf('%.4f', persisted_aic_nano / 1000000000.0) AS aic, datetime(updated_at, 'unixepoch', 'localtime') AS updated_at FROM conversations ORDER BY updated_at DESC LIMIT ${safeLimit};`;
    }
    return `SELECT datetime(created_at, 'unixepoch', 'localtime') AS observed_at, conversation_id, printf('%.4f', delta_aic_nano / 1000000000.0) AS delta_aic FROM aic_events ORDER BY created_at DESC LIMIT ${safeLimit};`;
}

const session = await joinSession({
    tools: [
        {
            name: "copilot_statusline_metrics_status",
            description: "Show install status for Copilot statusline metrics, including hook, settings, database, and schema.",
            parameters: { type: "object", properties: {} },
            skipPermission: true,
            handler: async () => {
                const settings = await readSettings().catch(() => ({}));
                const dbExists = existsSync(dbPath);
                const schema = dbExists
                    ? await run("sqlite3", [dbPath, "SELECT name, type FROM sqlite_master WHERE name IN ('conversations','aic_events','aic_daily','aic_weekly','aic_monthly') ORDER BY name;"])
                    : { ok: true, stdout: "" };
                return [
                    `Hook path: ${hookPath}`,
                    `Hook installed: ${existsSync(hookPath) ? "yes" : "no"}`,
                    `Settings statusLine command: ${settings.statusLine?.command || "(unset)"}`,
                    `Database path: ${dbPath}`,
                    `Database exists: ${dbExists ? "yes" : "no"}`,
                    `Schema objects:\n${schema.stdout.trim() || "(none)"}`,
                ].join("\n");
            },
        },
        {
            name: "copilot_statusline_metrics_query_aic",
            description: "Query persisted AIC usage by day, week, month, conversation, or recent event.",
            parameters: {
                type: "object",
                properties: {
                    period: {
                        type: "string",
                        enum: ["day", "week", "month", "conversation", "event"],
                        description: "Aggregation period to query.",
                    },
                    limit: {
                        type: "integer",
                        minimum: 1,
                        maximum: 365,
                        description: "Maximum number of rows to return.",
                    },
                },
                required: ["period"],
            },
            skipPermission: true,
            handler: async (args) => {
                if (!existsSync(dbPath)) {
                    return "Metrics database has not been created yet. Submit a prompt after installing the statusline hook.";
                }
                const sql = queryForPeriod(args.period, args.limit);
                const result = await run("sqlite3", ["-header", "-column", dbPath, sql]);
                if (!result.ok) {
                    return { resultType: "failure", textResultForLlm: result.stderr };
                }
                return result.stdout.trim() || "No AIC rows recorded yet.";
            },
        },
        {
            name: "copilot_statusline_metrics_install",
            description: "Configure Copilot CLI settings to use the installed statusline metrics hook.",
            parameters: { type: "object", properties: {} },
            handler: async () => {
                if (!existsSync(hookPath)) {
                    return {
                        resultType: "failure",
                        textResultForLlm: `Hook is missing at ${hookPath}. Run ./install.sh from the repository first.`,
                    };
                }
                const settings = await readSettings().catch(() => ({}));
                settings.statusLine = { type: "command", command: hookPath, padding: 1 };
                await writeSettings(settings);
                return `Configured statusLine.command to ${hookPath}. Restart Copilot CLI or run /restart to reload settings.`;
            },
        },
        {
            name: "copilot_statusline_metrics_uninstall",
            description: "Remove statusline metrics settings and installed files while keeping the metrics database.",
            parameters: { type: "object", properties: {} },
            handler: async () => {
                const settings = await readSettings().catch(() => ({}));
                if (settings.statusLine?.command === hookPath) {
                    delete settings.statusLine;
                    await writeSettings(settings);
                }
                await rm(hookPath, { force: true });
                await rm(join(copilotHome, "skills", "aic-metrics"), { recursive: true, force: true });
                return `Removed hook and skill. Metrics database remains at ${dbPath}.`;
            },
        },
    ],
});

await session.log("Copilot statusline metrics extension loaded.", { ephemeral: true });
