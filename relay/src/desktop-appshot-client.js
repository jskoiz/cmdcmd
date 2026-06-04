import { spawn } from "node:child_process";
import { logInfo } from "./logger.js";

export class DesktopAppshotClient {
  constructor(config, options = {}) {
    this.config = config;
    this.logger = options.logger ?? console;
    this.openCommand = options.openCommand ?? "/usr/bin/open";
  }

  async deliver(capture, stored) {
    const startedAt = Date.now();
    const appshot = this.config.appshot;

    logInfo(this.logger, "desktop_appshot.delivery_started", {
      captureId: capture.captureId,
      imagePath: stored.imagePath,
      openImageInViewer: appshot.openImageInViewer,
      viewerBundle: appshot.openImageInViewer ? appshot.viewerBundle : null
    });

    if (appshot.openImageInViewer) {
      await runCommand(
        this.openCommand,
        ["-b", appshot.viewerBundle, stored.imagePath],
        { timeoutMs: appshot.openTimeoutMs }
      );
      await delay(appshot.openDelayMs);
    }

    const helperArgs = buildHelperArgs(appshot);
    const helperResult = await runCommand(appshot.helperPath, helperArgs, {
      timeoutMs: appshot.helperTimeoutMs
    });

    logInfo(this.logger, "desktop_appshot.delivery_completed", {
      captureId: capture.captureId,
      helperPath: appshot.helperPath,
      helperArgs,
      stdout: helperResult.stdout || null,
      stderr: helperResult.stderr || null,
      durationMs: Date.now() - startedAt
    });

    return {
      status: "delivered",
      deliveryLane: "desktop-appshot",
      message: appshot.openImageInViewer
        ? "Triggered Desktop Appshot from phone screenshot"
        : "Triggered Desktop Appshot",
      imagePath: stored.imagePath,
      metadataPath: stored.metadataPath,
      targetBundle: targetBundleFor(appshot) ?? null
    };
  }
}

export function buildHelperArgs(appshot) {
  const args = [];

  if (appshot.hotkey) {
    args.push("--hotkey", appshot.hotkey);
  }

  const targetBundle = targetBundleFor(appshot);
  if (targetBundle) {
    args.push("--target-bundle", targetBundle);
  }

  if (appshot.noPrime) {
    args.push("--no-prime");
  }

  appendNumberOption(args, "--codex-delay", appshot.codexDelay);
  appendNumberOption(args, "--restore-delay", appshot.restoreDelay);
  appendNumberOption(args, "--hold-delay", appshot.holdDelay);

  return args;
}

function targetBundleFor(appshot) {
  return (
    appshot.targetBundle ||
    (appshot.openImageInViewer ? appshot.viewerBundle : undefined)
  );
}

function appendNumberOption(args, name, value) {
  if (value !== undefined) {
    args.push(name, String(value));
  }
}

function runCommand(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    let settled = false;

    const finish = (callback, value) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timeout);
      callback(value);
    };

    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      finish(
        reject,
        new Error(`${command} timed out after ${options.timeoutMs}ms.`)
      );
    }, options.timeoutMs);

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });

    child.on("error", (error) => {
      finish(reject, error);
    });

    child.on("close", (code, signal) => {
      if (code === 0) {
        finish(resolve, {
          stdout: trimmedOutput(stdout),
          stderr: trimmedOutput(stderr)
        });
        return;
      }

      const suffix = stderr ? `: ${trimmedOutput(stderr)}` : "";
      finish(
        reject,
        new Error(
          `${command} exited with ${signal ? `signal ${signal}` : `code ${code}`}${suffix}`
        )
      );
    });
  });
}

function trimmedOutput(value) {
  return value.trim().slice(0, 2000);
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
