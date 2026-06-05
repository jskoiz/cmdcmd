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
  const screenshotContext = formatScreenshotContext(capture.screenshotContext);
  const context = cleanMultiline(capture.context);
  const recognizedText = cleanMultiline(capture.recognizedText);

  if (screenshotContext) {
    sections.push(`Screenshot context:\n${screenshotContext}`);
  }

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

function formatScreenshotContext(context) {
  if (!context || typeof context !== "object") {
    return "";
  }

  const lines = [];
  const source = [humanizeSource(context.source), cleanInline(context.sourceDetail)]
    .filter(Boolean)
    .join(" - ");
  if (source) {
    lines.push(`Source: ${source}`);
  }

  const capturedAt = formatTimestamp(
    context.capturedAt,
    context.timeZoneIdentifier
  );
  if (capturedAt) {
    lines.push(`Captured: ${capturedAt}`);
  }

  const preparedAt = formatTimestamp(
    context.preparedAt,
    context.timeZoneIdentifier
  );
  if (preparedAt) {
    lines.push(`Prepared: ${preparedAt}`);
  }

  if (context.visibleApp?.name) {
    const evidence = Array.isArray(context.visibleApp.evidence)
      ? context.visibleApp.evidence.map(cleanInline).filter(Boolean)
      : [];
    const confidence = cleanInline(context.visibleApp.confidence);
    const suffix = [
      confidence ? `${confidence} inference` : "inferred",
      evidence.length > 0 ? `from ${evidence.join(", ")}` : ""
    ]
      .filter(Boolean)
      .join(" ");
    lines.push(
      `Visible app: ${cleanInline(context.visibleApp.name)} (${suffix})`
    );
  }

  const imageParts = [
    cleanInline(context.imageFilename),
    cleanInline(context.imageMimeType),
    formatDimensions(context.pixelWidth, context.pixelHeight),
    formatImageBytes(context.originalImageBytes, context.uploadImageBytes)
  ].filter(Boolean);
  if (imageParts.length > 0) {
    lines.push(`Image: ${imageParts.join("; ")}`);
  }

  if (context.ocrEnabled === false) {
    lines.push("OCR: off");
  } else {
    const ocrParts = [
      formatCount(context.ocrLineCount, "line"),
      formatCount(context.ocrCharacterCount, "character"),
      formatDuration(context.ocrDurationMs),
      formatConfidence(context.ocrAverageConfidence)
    ].filter(Boolean);
    const label = context.ocrTimedOut ? "OCR timed out" : "OCR";
    lines.push(ocrParts.length > 0 ? `${label}: ${ocrParts.join(", ")}` : label);
  }

  return lines.join("\n");
}

function humanizeSource(value) {
  const source = cleanInline(value);
  if (source === "mainApp") {
    return "Main app";
  }
  if (source === "shareExtension") {
    return "Share extension";
  }
  if (source === "shortcut") {
    return "Shortcut";
  }
  return source;
}

function formatTimestamp(value, timeZoneIdentifier) {
  if (!value) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  const options = {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
    timeZoneName: "short"
  };
  const timeZone = cleanInline(timeZoneIdentifier);
  if (timeZone) {
    options.timeZone = timeZone;
  }

  try {
    return new Intl.DateTimeFormat("en-US", options).format(date);
  } catch {
    return date.toISOString();
  }
}

function formatDimensions(width, height) {
  if (!Number.isInteger(width) || !Number.isInteger(height)) {
    return "";
  }
  return `${width}x${height}`;
}

function formatImageBytes(originalBytes, uploadBytes) {
  if (!Number.isInteger(originalBytes) && !Number.isInteger(uploadBytes)) {
    return "";
  }
  if (originalBytes === uploadBytes || !Number.isInteger(uploadBytes)) {
    return `${formatBytes(originalBytes)}`;
  }
  if (!Number.isInteger(originalBytes)) {
    return `${formatBytes(uploadBytes)} upload`;
  }
  return `${formatBytes(originalBytes)} original, ${formatBytes(uploadBytes)} upload`;
}

function formatBytes(bytes) {
  if (!Number.isInteger(bytes)) {
    return "";
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const digits = value >= 10 ? 1 : 2;
  return `${value.toFixed(digits)} ${units[unitIndex]}`;
}

function formatCount(value, singularLabel) {
  if (!Number.isInteger(value)) {
    return "";
  }
  return `${value} ${singularLabel}${value === 1 ? "" : "s"}`;
}

function formatDuration(milliseconds) {
  if (!Number.isInteger(milliseconds)) {
    return "";
  }
  if (milliseconds < 1000) {
    return `${milliseconds} ms`;
  }
  return `${(milliseconds / 1000).toFixed(1)} s`;
}

function formatConfidence(value) {
  if (typeof value !== "number") {
    return "";
  }
  return `avg confidence ${Math.round(value * 100)}%`;
}

function cleanInline(value) {
  return typeof value === "string"
    ? value.replaceAll(/\s+/g, " ").trim()
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
