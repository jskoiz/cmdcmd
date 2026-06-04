import os from "node:os";
import path from "node:path";
import { existsSync } from "node:fs";

const VALID_SANDBOX_MODES = new Set([
  "read-only",
  "workspace-write",
  "danger-full-access"
]);
const VALID_APPROVAL_POLICIES = new Set([
  "never",
  "on-request",
  "on-failure",
  "untrusted"
]);
const VALID_WEB_SEARCH_MODES = new Set(["disabled", "cached", "live"]);
const VALID_DELIVERY_MODES = new Set(["app-server", "desktop-appshot"]);
const VALID_APPSHOT_HOTKEYS = new Set([
  "DoubleCommand",
  "DoubleOption",
  "DoubleShift"
]);

export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigError";
    this.statusCode = 500;
  }
}

export function loadConfig(env = process.env, options = {}) {
  const cwd = options.cwd ?? process.cwd();
  const defaultCodexCwd = options.defaultCodexCwd ?? cwd;
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
  const codexCwd = resolveConfiguredPath(
    trim(env.CODEXSHOT_CODEX_CWD) || defaultCodexCwd,
    cwd
  );
  const sandboxMode = parseEnum(
    trim(env.CODEXSHOT_CODEX_SANDBOX) || "read-only",
    VALID_SANDBOX_MODES,
    "CODEXSHOT_CODEX_SANDBOX"
  );
  const approvalPolicy = parseEnum(
    trim(env.CODEXSHOT_CODEX_APPROVAL_POLICY) || "never",
    VALID_APPROVAL_POLICIES,
    "CODEXSHOT_CODEX_APPROVAL_POLICY"
  );
  const webSearchMode = parseEnum(
    trim(env.CODEXSHOT_CODEX_WEB_SEARCH_MODE) || "disabled",
    VALID_WEB_SEARCH_MODES,
    "CODEXSHOT_CODEX_WEB_SEARCH_MODE"
  );
  const dryRun = parseBoolean(env.CODEXSHOT_DRY_RUN);
  const deliveryMode = parseEnum(
    trim(env.CODEXSHOT_DELIVERY_MODE) || "app-server",
    VALID_DELIVERY_MODES,
    "CODEXSHOT_DELIVERY_MODE"
  );
  const appshotHelperPath = trim(env.CODEXSHOT_APPSHOT_HELPER);

  if (deliveryMode === "desktop-appshot" && !dryRun && !appshotHelperPath) {
    throw new ConfigError(
      "CODEXSHOT_APPSHOT_HELPER is required when CODEXSHOT_DELIVERY_MODE=desktop-appshot."
    );
  }

  return {
    token,
    host,
    port,
    deliveryMode,
    inboxDir,
    maxBodyBytes: parsePositiveInteger(
      env.CODEXSHOT_MAX_BODY_BYTES ?? "12500000",
      "CODEXSHOT_MAX_BODY_BYTES"
    ),
    dryRun,
    codex: {
      binaryPath:
        trim(env.CODEXSHOT_CODEX_BIN) ||
        defaultCodexBinaryPath(),
      workingDirectory: codexCwd,
      defaultThreadHint:
        trim(env.CODEXSHOT_CODEX_THREAD_ID) ||
        trim(env.CODEX_THREAD_ID) ||
        undefined,
      model: trim(env.CODEXSHOT_CODEX_MODEL) || undefined,
      sandboxMode,
      approvalPolicy,
      webSearchMode,
      requestTimeoutMs: parsePositiveInteger(
        env.CODEXSHOT_CODEX_REQUEST_TIMEOUT_MS ?? "15000",
        "CODEXSHOT_CODEX_REQUEST_TIMEOUT_MS"
      ),
      turnTimeoutMs: parsePositiveInteger(
        env.CODEXSHOT_CODEX_TURN_TIMEOUT_MS ?? "600000",
        "CODEXSHOT_CODEX_TURN_TIMEOUT_MS"
      ),
      skipGitRepoCheck: parseBoolean(env.CODEXSHOT_CODEX_SKIP_GIT_CHECK)
    },
    appshot: {
      helperPath: appshotHelperPath
        ? resolveConfiguredPath(appshotHelperPath, cwd)
        : "",
      hotkey: parseOptionalEnum(
        trim(env.CODEXSHOT_APPSHOT_HOTKEY),
        VALID_APPSHOT_HOTKEYS,
        "CODEXSHOT_APPSHOT_HOTKEY"
      ),
      targetBundle: trim(env.CODEXSHOT_APPSHOT_TARGET_BUNDLE) || undefined,
      openImageInViewer: parseBooleanDefault(
        env.CODEXSHOT_APPSHOT_OPEN_VIEWER,
        true
      ),
      viewerBundle:
        trim(env.CODEXSHOT_APPSHOT_VIEWER_BUNDLE) || "com.apple.Preview",
      openDelayMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_OPEN_DELAY_MS ?? "750",
        "CODEXSHOT_APPSHOT_OPEN_DELAY_MS"
      ),
      openTimeoutMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_OPEN_TIMEOUT_MS ?? "5000",
        "CODEXSHOT_APPSHOT_OPEN_TIMEOUT_MS"
      ),
      helperTimeoutMs: parsePositiveInteger(
        env.CODEXSHOT_APPSHOT_HELPER_TIMEOUT_MS ?? "30000",
        "CODEXSHOT_APPSHOT_HELPER_TIMEOUT_MS"
      ),
      noPrime: parseBoolean(env.CODEXSHOT_APPSHOT_NO_PRIME),
      codexDelay: parseOptionalPositiveNumber(
        env.CODEXSHOT_APPSHOT_CODEX_DELAY,
        "CODEXSHOT_APPSHOT_CODEX_DELAY"
      ),
      restoreDelay: parseOptionalPositiveNumber(
        env.CODEXSHOT_APPSHOT_RESTORE_DELAY,
        "CODEXSHOT_APPSHOT_RESTORE_DELAY"
      ),
      holdDelay: parseOptionalPositiveNumber(
        env.CODEXSHOT_APPSHOT_HOLD_DELAY,
        "CODEXSHOT_APPSHOT_HOLD_DELAY"
      )
    }
  };
}

function defaultCodexBinaryPath() {
  const bundledCodex = "/Applications/Codex.app/Contents/Resources/codex";
  return existsSync(bundledCodex) ? bundledCodex : "codex";
}

function trim(value) {
  return typeof value === "string" ? value.trim() : "";
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

function parseEnum(value, allowed, name) {
  if (!allowed.has(value)) {
    throw new ConfigError(`${name} must be one of: ${[...allowed].join(", ")}.`);
  }
  return value;
}

function parseOptionalEnum(value, allowed, name) {
  return value ? parseEnum(value, allowed, name) : undefined;
}

function parseOptionalPositiveNumber(value, name) {
  const trimmed = trim(value);
  if (!trimmed) {
    return undefined;
  }

  const parsed = Number.parseFloat(trimmed);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new ConfigError(`${name} must be a positive number.`);
  }
  return parsed;
}

function resolveConfiguredPath(value, cwd) {
  if (value.startsWith("~/")) {
    return path.join(os.homedir(), value.slice(2));
  }
  return path.resolve(cwd, value);
}
