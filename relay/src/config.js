import os from "node:os";
import path from "node:path";

const OBSOLETE_ENV_KEYS = [
  "CMDCMD_DELIVERY_MODE",
  "CMDCMD_DRY_RUN",
  "CMDCMD_CODEX_CWD",
  "CMDCMD_CODEX_THREAD_ID",
  "CODEX_THREAD_ID",
  "CMDCMD_CODEX_BIN",
  "CMDCMD_CODEX_MODEL",
  "CMDCMD_CODEX_SANDBOX",
  "CMDCMD_CODEX_APPROVAL_POLICY",
  "CMDCMD_CODEX_WEB_SEARCH_MODE",
  "CMDCMD_CODEX_REQUEST_TIMEOUT_MS",
  "CMDCMD_CODEX_TURN_TIMEOUT_MS",
  "CMDCMD_APPSHOT_HELPER",
  "CMDCMD_APPSHOT_HOTKEY",
  "CMDCMD_APPSHOT_TARGET_BUNDLE",
  "CMDCMD_APPSHOT_NO_PRIME",
  "CMDCMD_APPSHOT_CODEX_DELAY",
  "CMDCMD_APPSHOT_RESTORE_DELAY",
  "CMDCMD_APPSHOT_HOLD_DELAY"
];

export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigError";
    this.statusCode = 500;
  }
}

export function loadConfig(env = process.env, options = {}) {
  const cwd = options.cwd ?? process.cwd();
  rejectObsoleteEnv(env);
  const token = trim(env.CMDCMD_RELAY_TOKEN);

  if (!token) {
    throw new ConfigError("CMDCMD_RELAY_TOKEN is required.");
  }

  const host = trim(env.CMDCMD_HOST) || "127.0.0.1";
  const port = parsePort(env.CMDCMD_PORT ?? "8787");
  const inboxDir = resolveConfiguredPath(
    trim(env.CMDCMD_INBOX_DIR) ||
      path.join(os.homedir(), ".cmd-cmd-relay", "inbox"),
    cwd
  );

  return {
    token,
    host,
    port,
    inboxDir,
    maxBodyBytes: parsePositiveInteger(
      env.CMDCMD_MAX_BODY_BYTES ?? "12500000",
      "CMDCMD_MAX_BODY_BYTES"
    ),
    appshot: {
      openImageInViewer: parseBooleanDefault(
        env.CMDCMD_APPSHOT_OPEN_VIEWER,
        true
      ),
      viewerBundle:
        trim(env.CMDCMD_APPSHOT_VIEWER_BUNDLE) || "com.apple.Preview",
      closeViewerWindow: parseBooleanDefault(
        env.CMDCMD_APPSHOT_CLOSE_VIEWER,
        true
      ),
      openDelayMs: parsePositiveInteger(
        env.CMDCMD_APPSHOT_OPEN_DELAY_MS ?? "750",
        "CMDCMD_APPSHOT_OPEN_DELAY_MS"
      ),
      openTimeoutMs: parsePositiveInteger(
        env.CMDCMD_APPSHOT_OPEN_TIMEOUT_MS ?? "5000",
        "CMDCMD_APPSHOT_OPEN_TIMEOUT_MS"
      ),
      codexBundle:
        trim(env.CMDCMD_APPSHOT_CODEX_BUNDLE) || "com.openai.codex",
      pasteDelayMs: parsePositiveInteger(
        env.CMDCMD_APPSHOT_PASTE_DELAY_MS ?? "400",
        "CMDCMD_APPSHOT_PASTE_DELAY_MS"
      ),
      pasteTimeoutMs: parsePositiveInteger(
        env.CMDCMD_APPSHOT_PASTE_TIMEOUT_MS ?? "10000",
        "CMDCMD_APPSHOT_PASTE_TIMEOUT_MS"
      )
    }
  };
}

function trim(value) {
  return typeof value === "string" ? value.trim() : "";
}

function rejectObsoleteEnv(env) {
  const obsoleteKey = OBSOLETE_ENV_KEYS.find((key) => trim(env[key]));
  if (obsoleteKey) {
    throw new ConfigError(
      `${obsoleteKey} is no longer supported. Desktop Appshot is the only relay delivery path.`
    );
  }
}

function parsePort(value) {
  const port = Number.parseInt(value, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new ConfigError("CMDCMD_PORT must be an integer from 1 to 65535.");
  }
  return port;
}

function parsePositiveInteger(value, name) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new ConfigError(`${name} must be a positive integer.`);
  }
  return parsed;
}

function parseBoolean(value) {
  return ["1", "true", "yes", "on"].includes(trim(value).toLowerCase());
}

function parseBooleanDefault(value, defaultValue) {
  return trim(value) ? parseBoolean(value) : defaultValue;
}

function resolveConfiguredPath(value, cwd) {
  if (value.startsWith("~/")) {
    return path.join(os.homedir(), value.slice(2));
  }
  return path.resolve(cwd, value);
}
