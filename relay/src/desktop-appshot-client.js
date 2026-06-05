import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import { ensureDesktopHelper } from "./desktop-helper.js";
import { logInfo } from "./logger.js";

export class DesktopAppshotClient {
  constructor(config, options = {}) {
    this.config = config;
    this.logger = options.logger ?? console;
    this.openCommand = options.openCommand ?? "/usr/bin/open";
    this.runCommand = options.runCommand ?? runCommand;
    this.desktopHelperCommand = options.desktopHelperCommand;
    this.ensureDesktopHelper = options.ensureDesktopHelper ?? ensureDesktopHelper;
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
      await this.runCommand(
        this.openCommand,
        ["-b", appshot.viewerBundle, stored.imagePath],
        { timeoutMs: appshot.openTimeoutMs }
      );
      await delay(appshot.openDelayMs);
    }

    const helperCommand =
      this.desktopHelperCommand ??
      (await this.ensureDesktopHelper({
        runCommand: this.runCommand
      }));
    const textPath = await writeAttachmentTextIfNeeded(
      stored.metadataPath,
      buildDesktopAttachmentText(capture)
    );
    const helperResult = await this.runCommand(
      helperCommand,
      buildDesktopHelperArgs(stored.imagePath, appshot, { textPath }),
      { timeoutMs: appshot.pasteTimeoutMs }
    );

    logInfo(this.logger, "desktop_appshot.delivery_completed", {
      captureId: capture.captureId,
      codexBundle: appshot.codexBundle,
      helperCommand,
      stdout: helperResult.stdout || null,
      stderr: helperResult.stderr || null,
      durationMs: Date.now() - startedAt
    });

    return {
      status: "delivered",
      deliveryLane: "desktop-appshot",
      message: "Attached phone screenshot in the frontmost Codex chat",
      imagePath: stored.imagePath,
      metadataPath: stored.metadataPath,
      targetBundle: appshot.codexBundle
    };
  }
}

export function buildDesktopHelperArgs(imagePath, appshot, options = {}) {
  const args = [
    "--image-path",
    imagePath,
    "--codex-bundle",
    appshot.codexBundle,
    "--focus-delay-ms",
    String(appshot.pasteDelayMs),
    "--composer-bottom-offset",
    "70"
  ];

  if (options.textPath) {
    args.push("--text-path", options.textPath);
  }

  if (appshot.openImageInViewer && appshot.closeViewerWindow) {
    args.push("--viewer-bundle", appshot.viewerBundle, "--close-viewer");
  }

  return args;
}

export function buildDesktopAttachmentText(capture) {
  const sections = [];
  const context = cleanMultiline(capture.context);
  const recognizedText = cleanMultiline(capture.recognizedText);

  if (context) {
    sections.push(`Context:\n${context}`);
  }

  if (recognizedText) {
    sections.push(`OCR text:\n${recognizedText}`);
  }

  return sections.join("\n\n");
}

async function writeAttachmentTextIfNeeded(metadataPath, text) {
  if (!text) {
    return null;
  }

  const textPath = metadataPath.endsWith(".json")
    ? `${metadataPath.slice(0, -5)}.txt`
    : `${metadataPath}.txt`;
  await fs.writeFile(textPath, `${text}\n`, { mode: 0o600 });
  return textPath;
}

function cleanMultiline(value) {
  return typeof value === "string"
    ? value.replaceAll("\r\n", "\n").replaceAll("\r", "\n").trim()
    : "";
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
