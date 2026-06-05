import os from "node:os";
import path from "node:path";

const OBSOLETE_ENV_KEYS = [
  "CODEXSHOT_DELIVERY_MODE",
  "CODEXSHOT_DRY_RUN",
  "CODEXSHOT_CODEX_CWD",
  "CODEXSHOT_CODEX_THREAD_ID",
  "CODEX_THREAD_ID",
  "CODEXSHOT_CODEX_BIN",
  "CODEXSHOT_CODEX_MODEL",
  "CODEXSHOT_CODEX_SANDBOX",
  "CODEXSHOT_CODEX_APPROVAL_POLICY",
  "CODEXSHOT_CODEX_WEB_SEARCH_MODE",
  "CODEXSHOT_CODEX_REQUEST_TIMEOUT_MS",
  "CODEXSHOT_CODEX_TURN_TIMEOUT_MS",
  "CODEXSHOT_APPSHOT_HELPER",
  "CODEXSHOT_APPSHOT_HOTKEY",
  "CODEXSHOT_APPSHOT_TARGET_BUNDLE",
  "CODEXSHOT_APPSHOT_NO_PRIME",
  "CODEXSHOT_APPSHOT_CODEX_DELAY",
  "CODEXSHOT_APPSHOT_RESTORE_DELAY",
  "CODEXSHOT_APPSHOT_HOLD_DELAY"
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
  const token = trim(env.CODEXSHOT_RELAY_TOKEN);

  if (!token) {
    throw new ConfigError("CODEXSHOT_RELAY_TOKEN is required.");
  }

  const host = trim(env.CODEXSHOT_HOST) || "127.0.0.1";
  const port = parsePort(env.CODEXSHOT_PORT ?? "8787");
  const inboxDir = resolveConfiguredPath(
    trim(env.CODEXSHOT_INBOX_DIR) ||
      path.join(os.homedir(), ".cmd-cmd-relay", "inbox"),
    cwd
  );

  return {
    token,
    host,
    port,
    inboxDir,
    maxBodyBytes: parsePositiveInteger(
      env.CODEXSHOT_MAX_BODY_BYTES ?? "12500000",
      "CODEXSHOT_MAX_BODY_BYTES"
    ),
    appshot: {
      openImageInViewer: parseBooleanDefault(
        env.CODEXSHOT_APPSHOT_OPEN_VIEWER,
        false
      ),
      viewerBundle:
        trim(env.CODEXSHOT_APPSHOT_VIEWER_BUNDLE) || "com.apple.Preview",
      closeViewerWindow: parseBooleanDefault(
        env.CODEXSHOT_APPSHOT_CLOSE_VIEWER,
        true
      ),
      openDelayMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_OPEN_DELAY_MS ?? "750",
        "CODEXSHOT_APPSHOT_OPEN_DELAY_MS"
      ),
      openTimeoutMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_OPEN_TIMEOUT_MS ?? "5000",
        "CODEXSHOT_APPSHOT_OPEN_TIMEOUT_MS"
      ),
      codexBundle:
        trim(env.CODEXSHOT_APPSHOT_CODEX_BUNDLE) || "com.openai.codex",
      pasteDelayMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_PASTE_DELAY_MS ?? "400",
        "CODEXSHOT_APPSHOT_PASTE_DELAY_MS"
      ),
      pasteTimeoutMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_PASTE_TIMEOUT_MS ?? "10000",
        "CODEXSHOT_APPSHOT_PASTE_TIMEOUT_MS"
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
    throw new ConfigError("CODEXSHOT_PORT must be an integer from 1 to 65535.");
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
