import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import { ensureDesktopHelper } from "./desktop-helper.js";
import { logInfo } from "./logger.js";

const MAX_OCR_ATTACHMENT_LINES = 16;
const MAX_OCR_ATTACHMENT_CHARS = 1200;
const IGNORED_OCR_STATUS_LINES = new Set(["phone"]);
const ALLOWED_OCR_SYMBOLS = new Set(".,:;!?%+#@&()/-");

export class DesktopAttachmentClient {
  constructor(config, options = {}) {
    this.config = config;
    this.logger = options.logger ?? console;
    this.runCommand = options.runCommand ?? runCommand;
    this.desktopHelperCommand = options.desktopHelperCommand;
    this.ensureDesktopHelper = options.ensureDesktopHelper ?? ensureDesktopHelper;
  }

  async deliver(capture, stored) {
    const startedAt = Date.now();
    const desktopAttachment = this.config.desktopAttachment;

    logInfo(this.logger, "desktop_attachment.delivery_started", {
      captureId: capture.captureId,
      imagePath: stored.imagePath,
      codexBundle: desktopAttachment.codexBundle
    });

    const helperCommand =
      this.desktopHelperCommand ??
      (await this.ensureDesktopHelper({
        runCommand: this.runCommand
      }));
    const contextPath = await writeAttachmentTextIfNeeded(
      stored.metadataPath,
      buildDesktopAttachmentText(capture)
    );
    const helperResult = await this.runCommand(
      helperCommand,
      buildDesktopHelperArgs(stored.imagePath, desktopAttachment, {
        contextPath
      }),
      { timeoutMs: desktopAttachment.pasteTimeoutMs }
    );

    logInfo(this.logger, "desktop_attachment.delivery_completed", {
      captureId: capture.captureId,
      codexBundle: desktopAttachment.codexBundle,
      helperCommand,
      stdout: helperResult.stdout || null,
      stderr: helperResult.stderr || null,
      durationMs: Date.now() - startedAt
    });

    return {
      status: "delivered",
      deliveryLane: "desktop-attachment",
      message: "Screenshot sent to Codex",
      imagePath: stored.imagePath,
      metadataPath: stored.metadataPath,
      targetBundle: desktopAttachment.codexBundle
    };
  }
}

export function buildDesktopHelperArgs(imagePath, desktopAttachment, options = {}) {
  const args = [
    "--image-path",
    imagePath,
    "--codex-bundle",
    desktopAttachment.codexBundle,
    "--focus-delay-ms",
    String(desktopAttachment.pasteDelayMs),
    "--composer-bottom-offset",
    "70"
  ];

  if (options.contextPath) {
    args.push("--context-path", options.contextPath);
  }

  return args;
}

export function buildDesktopAttachmentText(capture) {
  const sections = [];
  const context = cleanMultiline(capture.context);
  const rawRecognizedText = cleanMultiline(capture.recognizedText);
  const recognizedText = cleanOCRTextForAttachment(rawRecognizedText);
  const screenshotContext = formatScreenshotContext(capture.screenshotContext, {
    rawRecognizedText,
    recognizedText
  });

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

function cleanOCRTextForAttachment(value) {
  const text = cleanMultiline(value);
  if (!text) {
    return "";
  }

  const lines = [];
  const seenKeys = new Set();
  let characterCount = 0;

  for (const rawLine of text.split("\n")) {
    const line = cleanOCRLine(rawLine);
    if (!line || !isInformativeOCRLine(line)) {
      continue;
    }

    const key = ocrDedupeKey(line);
    if (!key || seenKeys.has(key)) {
      continue;
    }

    const nextCharacterCount = characterCount + line.length + (lines.length ? 1 : 0);
    if (lines.length > 0 && nextCharacterCount > MAX_OCR_ATTACHMENT_CHARS) {
      break;
    }

    lines.push(line);
    seenKeys.add(key);
    characterCount = nextCharacterCount;

    if (lines.length >= MAX_OCR_ATTACHMENT_LINES) {
      break;
    }
  }

  return lines.join("\n");
}

function cleanOCRLine(value) {
  let line = cleanInline(value);
  line = stripOCREdgeJunk(line);

  const tokens = line.split(" ").filter(Boolean);
  while (tokens.length > 1 && isLeadingOCRArtifact(tokens[0])) {
    tokens.shift();
  }

  return stripOCREdgeJunk(tokens.join(" "));
}

function stripOCREdgeJunk(value) {
  return value
    .replace(/^[^\p{L}\p{N}]+/u, "")
    .replace(/[^\p{L}\p{N}.!?%]+$/u, "")
    .trim();
}

function isInformativeOCRLine(line) {
  const key = ocrDedupeKey(line);
  if (!key || IGNORED_OCR_STATUS_LINES.has(key)) {
    return false;
  }

  if (/^\d{1,2}:\d{2}$/.test(line)) {
    return false;
  }

  const letters = countMatches(line, /\p{L}/gu);
  if (letters === 0) {
    return false;
  }

  const usefulWords = key
    .split(" ")
    .filter((word) => word.length >= 3 && /\p{L}/u.test(word));
  if (usefulWords.length === 0) {
    return false;
  }

  const digits = countMatches(line, /\p{N}/gu);
  const noisySymbols = Array.from(line).filter((character) => {
    if (/[\p{L}\p{N}\s]/u.test(character)) {
      return false;
    }
    return !ALLOWED_OCR_SYMBOLS.has(character);
  }).length;
  return noisySymbols <= letters + digits;
}

function isLeadingOCRArtifact(token) {
  if (/^\p{N}+$/u.test(token)) {
    return true;
  }
  if (/^[^\p{L}\p{N}]+$/u.test(token)) {
    return true;
  }

  const normalized = token.toLocaleLowerCase();
  return normalized.length === 1 && normalized !== "a" && normalized !== "i";
}

function ocrDedupeKey(value) {
  return value
    .normalize("NFKD")
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replaceAll(/\s+/g, " ")
    .trim();
}

function countMatches(value, pattern) {
  return Array.from(value.matchAll(pattern)).length;
}

function textStats(value) {
  const text = cleanMultiline(value);
  if (!text) {
    return { lineCount: 0, characterCount: 0 };
  }
  return {
    lineCount: text.split("\n").filter((line) => line.trim()).length,
    characterCount: text.length
  };
}

function formatScreenshotContext(context, ocrText = {}) {
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
    lines.push(formatOCRSummary(context, ocrText));
  }

  return lines.join("\n");
}

function formatOCRSummary(context, { rawRecognizedText = "", recognizedText = "" } = {}) {
  const duration = formatDuration(context.ocrDurationMs);
  const confidence = formatConfidence(context.ocrAverageConfidence);

  if (context.ocrTimedOut) {
    return ["OCR: timed out", duration].filter(Boolean).join(", ");
  }

  const cleanedStats = textStats(recognizedText);
  const rawStats = textStats(rawRecognizedText);
  const rawLineCount = Number.isInteger(context.ocrLineCount)
    ? context.ocrLineCount
    : rawStats.lineCount;
  const rawCharacterCount = Number.isInteger(context.ocrCharacterCount)
    ? context.ocrCharacterCount
    : rawStats.characterCount;

  if (cleanedStats.lineCount > 0) {
    const filtered = cleanedStats.lineCount < rawLineCount
      || cleanedStats.characterCount < rawCharacterCount;
    const lineLabel = `${cleanedStats.lineCount} ${filtered ? "useful " : ""}line${cleanedStats.lineCount === 1 ? "" : "s"}`;
    return [
      `OCR: ${lineLabel}`,
      formatCount(cleanedStats.characterCount, "character"),
      duration,
      confidence
    ]
      .filter(Boolean)
      .join(", ");
  }

  if (rawLineCount > 0 || rawCharacterCount > 0 || rawStats.lineCount > 0) {
    return ["OCR: noisy text omitted", duration].filter(Boolean).join(", ");
  }

  return ["OCR: no useful text", duration].filter(Boolean).join(", ");
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
