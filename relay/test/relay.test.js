import assert from "node:assert/strict";
import fs from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { loadConfig } from "../src/config.js";
import {
  buildDesktopAttachmentText,
  buildDesktopHelperArgs,
  DesktopAttachmentClient
} from "../src/desktop-attachment-client.js";
import { DESKTOP_HELPER_SOURCE } from "../src/desktop-helper.js";
import { createDeliveryStatusStore } from "../src/delivery-status.js";
import { createDeliveryQueue, deliverPayload } from "../src/relay.js";
import { createServer } from "../src/server.js";

const samplePayload = {
  schemaVersion: 2,
  captureId: "22222222-2222-4222-8222-222222222222",
  createdAt: "2026-06-04T12:00:00.000Z",
  source: "shortcut",
  sourceDetail: "Unit test",
  screenshotContext: {
    capturedAt: "2026-06-04T12:00:00.000Z",
    preparedAt: "2026-06-04T12:00:01.000Z",
    timeZoneIdentifier: "UTC",
    source: "shortcut",
    sourceDetail: "Unit test",
    imageFilename: "../unsafe name.png",
    imageMimeType: "image/png",
    pixelWidth: 8,
    pixelHeight: 8,
    originalImageBytes: 176,
    uploadImageBytes: 176,
    ocrEnabled: true,
    ocrDurationMs: 412,
    ocrLineCount: 1,
    ocrCharacterCount: 19,
    ocrTimedOut: false,
    ocrAverageConfidence: 0.89,
    visibleApp: {
      name: "Photos",
      confidence: "high",
      evidence: ["Library", "Collections", "Syncing Paused"]
    }
  },
  context: "Please review the screenshot.",
  recognizedText: "OCR from screenshot",
  imageFilename: "../unsafe name.png",
  imageMimeType: "image/png",
  imageBase64:
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAACKADAAQAAAABAAAACAAAAACVhHtSAAAAGklEQVQIHWMW2Nkoy776XwcPGsnEgAMMTgkAzi8JTigyXpYAAAAASUVORK5CYII="
};

test("deliverPayload validates, stores, and queues Codex Desktop delivery", async () => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const calls = [];
  let resolveDelivery;
  const deliveryStarted = new Promise((resolve) => {
    resolveDelivery = resolve;
  });
  const result = await deliverPayload(samplePayload, {
    config: { inboxDir },
    deliveryQueue: createDeliveryQueue(),
    deliveryStatusStore: createDeliveryStatusStore(),
    codexClient: {
      async deliver(capture, stored) {
        calls.push({ capture, stored });
        resolveDelivery();
        return {
          status: "delivered",
          deliveryLane: "desktop-attachment",
          message: "Screenshot sent to Codex"
        };
      }
    }
  });

  assert.equal(result.status, "accepted");
  assert.equal(
    result.statusUrl,
    "/v1/captures/22222222-2222-4222-8222-222222222222/status"
  );
  assert.match(result.imagePath, /unsafe-name\.png$/);
  await deliveryStarted;
  assert.equal(calls.length, 1);

  const image = await fs.readFile(result.imagePath);
  assert.ok(image.length > 0);

  const metadata = JSON.parse(await fs.readFile(result.metadataPath, "utf8"));
  assert.equal(metadata.captureId, samplePayload.captureId);
  assert.deepEqual(metadata.screenshotContext, samplePayload.screenshotContext);
  assert.equal(metadata.imagePath, result.imagePath);
});

test("loadConfig includes Codex Desktop attachment defaults", () => {
  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret"
    },
    { cwd: process.cwd() }
  );

  assert.equal(config.desktopAttachment.codexBundle, "com.openai.codex");
  assert.equal(config.desktopAttachment.pasteDelayMs, 400);
});

test("loadConfig rejects obsolete relay delivery settings", () => {
  assert.throws(
    () =>
      loadConfig(
        {
          CMDCMD_RELAY_TOKEN: "secret",
          CMDCMD_DELIVERY_MODE: "app-server"
        },
        { cwd: process.cwd() }
      ),
    /CMDCMD_DELIVERY_MODE is no longer supported/
  );
});

test("loadConfig rejects obsolete Appshot helper settings", () => {
  assert.throws(
    () =>
      loadConfig(
        {
          CMDCMD_RELAY_TOKEN: "secret",
          CMDCMD_APPSHOT_HELPER: "/tmp/helper"
        },
        { cwd: process.cwd() }
      ),
    /CMDCMD_APPSHOT_HELPER is no longer supported/
  );
});

test("loadConfig rejects obsolete Appshot attachment settings", () => {
  assert.throws(
    () =>
      loadConfig(
        {
          CMDCMD_RELAY_TOKEN: "secret",
          CMDCMD_APPSHOT_CODEX_BUNDLE: "com.openai.codex"
        },
        { cwd: process.cwd() }
      ),
    /CMDCMD_APPSHOT_CODEX_BUNDLE is no longer supported/
  );
});

test("DesktopAttachmentClient sends screenshot context as a text attachment", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmdcmd-attachment-"));
  const imagePath = path.join(tempDir, "image.png");
  await fs.writeFile(imagePath, Buffer.from(samplePayload.imageBase64, "base64"));
  const commands = [];

  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: tempDir,
      CMDCMD_DESKTOP_CODEX_BUNDLE: "com.openai.codex",
      CMDCMD_DESKTOP_PASTE_DELAY_MS: "1"
    },
    { cwd: tempDir }
  );
  const client = new DesktopAttachmentClient(config, {
    logger: { info() {}, error() {} },
    desktopHelperCommand: "/tmp/cmdcmd-desktop-helper",
    runCommand: async (command, args) => {
      commands.push({ command, args });
      return { stdout: "", stderr: "" };
    }
  });

  const result = await client.deliver(samplePayload, {
    imagePath,
    metadataPath: path.join(tempDir, "metadata.json")
  });

  assert.equal(result.status, "delivered");
  assert.equal(result.deliveryLane, "desktop-attachment");
  assert.equal(
    result.message,
    "Screenshot sent to Codex"
  );
  assert.equal(result.targetBundle, "com.openai.codex");
  const contextPath = path.join(tempDir, "metadata.txt");
  assert.equal(
    await fs.readFile(contextPath, "utf8"),
    [
      "Screenshot context:",
      "Source: Shortcut - Unit test",
      "Captured: Jun 04, 2026, 12:00:00 PM UTC",
      "Prepared: Jun 04, 2026, 12:00:01 PM UTC",
      "Visible app: Photos (high inference from Library, Collections, Syncing Paused)",
      "Image: ../unsafe name.png; image/png; 8x8; 176 B",
      "OCR: 1 line, 19 characters, 412 ms, avg confidence 89%",
      "",
      "Context:",
      "Please review the screenshot.",
      "",
      "OCR text:",
      "OCR from screenshot",
      ""
    ].join("\n")
  );
  assert.deepEqual(commands.map(({ command, args }) => [command, args[0]]), [
    ["/tmp/cmdcmd-desktop-helper", "--image-path"]
  ]);
  assert.deepEqual(commands[0].args, [
    "--image-path",
    imagePath,
    "--codex-bundle",
    "com.openai.codex",
    "--focus-delay-ms",
    "1",
    "--composer-bottom-offset",
    "70",
    "--context-path",
    contextPath
  ]);
});

test("DesktopAttachmentClient triggers without Preview by default", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmdcmd-attachment-"));
  const imagePath = path.join(tempDir, "image.png");
  await fs.writeFile(imagePath, Buffer.from(samplePayload.imageBase64, "base64"));
  const commands = [];

  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: tempDir,
      CMDCMD_DESKTOP_CODEX_BUNDLE: "com.openai.codex",
      CMDCMD_DESKTOP_PASTE_DELAY_MS: "1"
    },
    { cwd: tempDir }
  );
  const client = new DesktopAttachmentClient(config, {
    logger: { info() {}, error() {} },
    desktopHelperCommand: "/tmp/cmdcmd-desktop-helper",
    runCommand: async (command, args) => {
      commands.push({ command, args });
      return { stdout: "", stderr: "" };
    }
  });

  await client.deliver(samplePayload, {
    imagePath,
    metadataPath: path.join(tempDir, "metadata.json")
  });

  assert.deepEqual(commands.map(({ command }) => command), [
    "/tmp/cmdcmd-desktop-helper"
  ]);
  assert.equal(commands[0].args.includes("--viewer-bundle"), false);
  assert.equal(commands[0].args.includes("--close-viewer"), false);
  assert.equal(commands[0].args.includes("--text-path"), false);
  assert.equal(commands[0].args.includes("--window-title"), false);
});

test("desktop helper pastes screenshot and context as file attachments", () => {
  assert.match(
    DESKTOP_HELPER_SOURCE,
    /copyFilesToPasteboard\(attachmentPastePaths\(config: config\)\)/
  );
  assert.doesNotMatch(DESKTOP_HELPER_SOURCE, /NSImage\(contentsOfFile/);
  assert.doesNotMatch(DESKTOP_HELPER_SOURCE, /setString\(url\.absoluteString/);
});

test("buildDesktopHelperArgs configures screenshot and text attachment paste", () => {
  assert.deepEqual(
    buildDesktopHelperArgs(
      "/tmp/screenshot.png",
      {
        codexBundle: "com.openai.codex",
        pasteDelayMs: 250
      },
      {
        contextPath: "/tmp/screenshot.txt"
      }
    ),
    [
      "--image-path",
      "/tmp/screenshot.png",
      "--codex-bundle",
      "com.openai.codex",
      "--focus-delay-ms",
      "250",
      "--composer-bottom-offset",
      "70",
      "--context-path",
      "/tmp/screenshot.txt",
    ]
  );
});

test("buildDesktopAttachmentText builds plain Accessibility context", () => {
  assert.equal(
    buildDesktopAttachmentText(samplePayload),
    [
      "Screenshot context:",
      "Source: Shortcut - Unit test",
      "Captured: Jun 04, 2026, 12:00:00 PM UTC",
      "Prepared: Jun 04, 2026, 12:00:01 PM UTC",
      "Visible app: Photos (high inference from Library, Collections, Syncing Paused)",
      "Image: ../unsafe name.png; image/png; 8x8; 176 B",
      "OCR: 1 line, 19 characters, 412 ms, avg confidence 89%",
      "",
      "Context:",
      "Please review the screenshot.",
      "",
      "OCR text:",
      "OCR from screenshot"
    ].join("\n")
  );
  assert.equal(
    buildDesktopAttachmentText({
      context: "",
      recognizedText: "  Visible text  "
    }),
    [
      "OCR text:",
      "Visible text"
    ].join("\n")
  );
});

test("buildDesktopAttachmentText leaves context as plain text", () => {
  assert.equal(
    buildDesktopAttachmentText({
      imageFilename: "unsafe \"<name>&.png",
      screenshotContext: {
        visibleApp: {
          name: "App \"<One>&",
          confidence: "high",
          evidence: ["A&B"]
        }
      },
      context: "Compare A < B & C > D",
      recognizedText: ""
    }),
    [
      "Screenshot context:",
      "Visible app: App \"<One>& (high inference from A&B)",
      "OCR: no useful text",
      "",
      "Context:",
      "Compare A < B & C > D"
    ].join("\n")
  );
});

test("buildDesktopAttachmentText filters noisy OCR lines", () => {
  const noisyPayload = {
    ...samplePayload,
    source: "mainApp",
    sourceDetail: "",
    context: "",
    screenshotContext: {
      ...samplePayload.screenshotContext,
      source: "mainApp",
      sourceDetail: "",
      ocrLineCount: 16,
      ocrCharacterCount: 140,
      visibleApp: {
        name: "cmd+cmd",
        confidence: "medium",
        evidence: ["OCR ready", "Thread hint"]
      }
    },
    recognizedText: [
      "4 Phone",
      "8:04",
      "+",
      "*",
      "•••",
      "3:19",
      "• | 5 5",
      "26 + H",
      "•••",
      "cmd+cmd",
      "& OCR ready",
      "U Thread hint",
      ") Sending to Codex",
      "* Sending...",
      "Sending to Codex",
      "Sending..."
    ].join("\n")
  };

  assert.equal(
    buildDesktopAttachmentText(noisyPayload),
    [
      "Screenshot context:",
      "Source: Main app",
      "Captured: Jun 04, 2026, 12:00:00 PM UTC",
      "Prepared: Jun 04, 2026, 12:00:01 PM UTC",
      "Visible app: cmd+cmd (medium inference from OCR ready, Thread hint)",
      "Image: ../unsafe name.png; image/png; 8x8; 176 B",
      "OCR: 5 useful lines, 57 characters, 412 ms, avg confidence 89%",
      "",
      "OCR text:",
      "cmd+cmd",
      "OCR ready",
      "Thread hint",
      "Sending to Codex",
      "Sending..."
    ].join("\n")
  );
});

test("buildDesktopAttachmentText omits low-signal OCR text", () => {
  const noisyPayload = {
    ...samplePayload,
    context: "",
    screenshotContext: {
      ...samplePayload.screenshotContext,
      ocrLineCount: 5,
      ocrCharacterCount: 18
    },
    recognizedText: ["8:04", "+", "•••", "3:19", "5 5"].join("\n")
  };

  assert.equal(
    buildDesktopAttachmentText(noisyPayload),
    [
      "Screenshot context:",
      "Source: Shortcut - Unit test",
      "Captured: Jun 04, 2026, 12:00:00 PM UTC",
      "Prepared: Jun 04, 2026, 12:00:01 PM UTC",
      "Visible app: Photos (high inference from Library, Collections, Syncing Paused)",
      "Image: ../unsafe name.png; image/png; 8x8; 176 B",
      "OCR: noisy text omitted, 412 ms"
    ].join("\n")
  );
});

test("delivery status reports Codex Desktop progress honestly", () => {
  const store = createDeliveryStatusStore();
  const capture = {
    captureId: "55555555-5555-4555-8555-555555555555"
  };
  const stored = {
    imagePath: "/tmp/cmdcmd/image.png",
    metadataPath: "/tmp/cmdcmd/metadata.json"
  };

  const accepted = store.accept(capture, stored, "req_test");
  assert.equal(accepted.message, "Screenshot queued for Codex");

  const delivering = store.deliver(capture.captureId);
  assert.equal(delivering.message, "Sending screenshot to Codex");

  const delivered = store.complete(capture.captureId, {
    deliveryLane: "desktop-attachment"
  });
  assert.equal(
    delivered.message,
    "Screenshot sent to Codex"
  );
});

test("createServer requires bearer auth for capture posts", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: inboxDir
    },
    { cwd: process.cwd() }
  );
  const server = createServer({
    config,
    codexClient: {
      async deliver() {
        return {
          status: "delivered",
          deliveryLane: "desktop-attachment",
          message: "Screenshot sent to Codex"
        };
      }
    },
    logger: { error() {}, info() {} }
  });

  await listen(server);
  t.after(() => server.close());

  const url = `http://127.0.0.1:${server.address().port}/v1/captures`;
  const unauthorized = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(samplePayload)
  });
  assert.equal(unauthorized.status, 401);

  const authorized = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: "Bearer secret",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      ...samplePayload,
      captureId: "33333333-3333-4333-8333-333333333333"
    })
  });
  assert.equal(authorized.status, 202);
  const body = await authorized.json();
  assert.equal(body.status, "accepted");
  assert.equal(
    body.statusUrl,
    "/v1/captures/33333333-3333-4333-8333-333333333333/status"
  );
});

test("createServer exposes the Mac pairing page without bearer auth", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: inboxDir
    },
    { cwd: process.cwd() }
  );
  const server = createServer({
    config,
    codexClient: {
      async deliver() {
        throw new Error("Unexpected delivery");
      }
    },
    logger: { error() {}, info() {} }
  });

  await listen(server);
  t.after(() => server.close());

  const response = await fetch(`http://127.0.0.1:${server.address().port}/pair`);
  assert.equal(response.status, 200);
  const body = await response.text();
  assert.match(body, /cmd\+cmd relay is running/);
  assert.match(body, /\/v1\/captures/);
});

test("createServer exposes authenticated delivery status until completion", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: inboxDir
    },
    { cwd: process.cwd() }
  );
  let resolveDelivery;
  const deliveryCanFinish = new Promise((resolve) => {
    resolveDelivery = resolve;
  });
  const server = createServer({
    config,
    codexClient: {
      async deliver() {
        await deliveryCanFinish;
        return {
          status: "delivered",
          deliveryLane: "desktop-attachment",
          message: "Screenshot sent to Codex"
        };
      }
    },
    logger: { error() {}, info() {} }
  });

  await listen(server);
  t.after(() => server.close());

  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const postResponse = await fetch(`${baseUrl}/v1/captures`, {
    method: "POST",
    headers: {
      Authorization: "Bearer secret",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      ...samplePayload,
      captureId: "44444444-4444-4444-8444-444444444444"
    })
  });
  assert.equal(postResponse.status, 202);
  const accepted = await postResponse.json();

  const pending = await fetch(`${baseUrl}${accepted.statusUrl}`, {
    headers: { Authorization: "Bearer secret" }
  });
  assert.equal(pending.status, 200);
  const pendingBody = await pending.json();
  assert.equal(pendingBody.captureId, "44444444-4444-4444-8444-444444444444");
  assert.ok(["accepted", "delivering"].includes(pendingBody.status));

  resolveDelivery();
  const deliveredBody = await waitForStatus(
    `${baseUrl}${accepted.statusUrl}`,
    "secret",
    "delivered"
  );
  assert.equal(
    deliveredBody.message,
    "Screenshot sent to Codex"
  );
  assert.equal(deliveredBody.deliveryLane, "desktop-attachment");
});

test("createServer decodes non-ASCII JSON split across TCP chunks exactly once", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const config = loadConfig(
    { CMDCMD_RELAY_TOKEN: "secret", CMDCMD_INBOX_DIR: inboxDir },
    { cwd: process.cwd() }
  );
  const server = createServer({
    config,
    codexClient: {
      async deliver() {
        return { status: "delivered", deliveryLane: "desktop-attachment" };
      }
    },
    logger: { error() {}, info() {} }
  });
  await listen(server);
  t.after(() => server.close());

  const context = "Review café 🌺 exactly.";
  const body = Buffer.from(JSON.stringify({
    ...samplePayload,
    captureId: "66666666-6666-4666-8666-666666666666",
    context
  }));
  const flower = Buffer.from("🌺");
  const flowerIndex = body.indexOf(flower);
  assert.notEqual(flowerIndex, -1);
  const response = decodeRawResponse(await sendRawRequest(server.address().port, body, flowerIndex + 1));

  assert.match(response.head, /^HTTP\/1\.1 202 /);
  const responseBody = JSON.parse(response.body.toString("utf8"));
  const metadata = JSON.parse(await fs.readFile(responseBody.metadataPath, "utf8"));
  assert.equal(metadata.context, context);
});

test("createServer serializes desktop deliveries in capture acceptance order", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const config = loadConfig(
    { CMDCMD_RELAY_TOKEN: "secret", CMDCMD_INBOX_DIR: inboxDir },
    { cwd: process.cwd() }
  );
  const calls = [];
  let releaseFirst;
  const firstBlocked = new Promise((resolve) => { releaseFirst = resolve; });
  const server = createServer({
    config,
    codexClient: {
      async deliver(capture) {
        calls.push(capture.captureId);
        if (calls.length === 1) {
          await firstBlocked;
        }
        return { status: "delivered", deliveryLane: "desktop-attachment" };
      }
    },
    logger: { error() {}, info() {} }
  });
  await listen(server);
  t.after(() => server.close());

  const firstId = "77777777-7777-4777-8777-777777777777";
  const secondId = "88888888-8888-4888-8888-888888888888";
  const first = await postCapture(server, config.token, firstId);
  const second = await postCapture(server, config.token, secondId);
  assert.equal(first.status, 202);
  assert.equal(second.status, 202);
  assert.deepEqual(calls, [firstId]);

  releaseFirst();
  await waitFor(() => calls.length === 2);
  assert.deepEqual(calls, [firstId, secondId]);
});

test("createServer continues queued delivery after a rejection", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const config = loadConfig(
    { CMDCMD_RELAY_TOKEN: "secret", CMDCMD_INBOX_DIR: inboxDir },
    { cwd: process.cwd() }
  );
  const calls = [];
  const server = createServer({
    config,
    codexClient: {
      async deliver(capture) {
        calls.push(capture.captureId);
        if (calls.length === 1) {
          throw new Error("First delivery failed");
        }
        return { status: "delivered", deliveryLane: "desktop-attachment" };
      }
    },
    logger: { error() {}, info() {} }
  });
  await listen(server);
  t.after(() => server.close());

  const firstId = "99999999-9999-4999-8999-999999999999";
  const secondId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const first = await postCapture(server, config.token, firstId);
  const second = await postCapture(server, config.token, secondId);
  assert.equal(first.status, 202);
  assert.equal(second.status, 202);

  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const failed = await waitForStatus(`${baseUrl}/v1/captures/${firstId}/status`, config.token, "failed");
  const delivered = await waitForStatus(`${baseUrl}/v1/captures/${secondId}/status`, config.token, "delivered");
  assert.match(failed.message, /First delivery failed/);
  assert.equal(delivered.captureId, secondId);
  assert.deepEqual(calls, [firstId, secondId]);
});

test("createServer preserves maximum-body and malformed-JSON responses", async (t) => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmd-cmd-relay-"));
  const loaded = loadConfig(
    { CMDCMD_RELAY_TOKEN: "secret", CMDCMD_INBOX_DIR: inboxDir },
    { cwd: process.cwd() }
  );
  const server = createServer({
    config: { ...loaded, maxBodyBytes: 8 },
    codexClient: { async deliver() { throw new Error("Unexpected delivery"); } },
    logger: { error() {}, info() {} }
  });
  await listen(server);
  t.after(() => server.close());
  const url = `http://127.0.0.1:${server.address().port}/v1/captures`;
  const headers = { Authorization: "Bearer secret", "Content-Type": "application/json" };

  const oversized = await fetch(url, { method: "POST", headers, body: "{\"long\":true}" });
  assert.equal(oversized.status, 413);
  assert.deepEqual(await oversized.json(), { error: "Request body is too large." });

  const malformed = await fetch(url, { method: "POST", headers, body: "{" });
  assert.equal(malformed.status, 400);
  assert.deepEqual(await malformed.json(), { error: "Request body must be valid JSON." });
});

test("invalid payloads are rejected before storage", async () => {
  await assert.rejects(
    () =>
      deliverPayload(
        {
          ...samplePayload,
          imageMimeType: "text/plain"
        },
        {
          config: { inboxDir: os.tmpdir() },
          codexClient: {
            async deliver() {
              throw new Error("should not deliver");
            }
          }
        }
      ),
    /imageMimeType must be image\/png or image\/jpeg/
  );
});

test("obsolete payload fields are rejected before storage", async () => {
  await assert.rejects(
    () =>
      deliverPayload(
        {
          ...samplePayload,
          threadHint: "019e945a-df22-79a0-977d-5c25eb11ba43"
        },
        {
          config: { inboxDir: os.tmpdir() },
          codexClient: {
            async deliver() {
              throw new Error("should not deliver");
            }
          }
        }
      ),
    /Unsupported payload field: threadHint/
  );
});

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
}

async function postCapture(server, token, captureId) {
  return fetch(`http://127.0.0.1:${server.address().port}/v1/captures`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ ...samplePayload, captureId })
  });
}

function sendRawRequest(port, body, splitIndex) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(port, "127.0.0.1");
    const responseChunks = [];
    socket.on("error", reject);
    socket.on("data", (chunk) => responseChunks.push(chunk));
    socket.on("end", () => resolve(Buffer.concat(responseChunks)));
    socket.on("connect", () => {
      socket.write([
        "POST /v1/captures HTTP/1.1",
        "Host: 127.0.0.1",
        "Authorization: Bearer secret",
        "Content-Type: application/json",
        `Content-Length: ${body.length}`,
        "Connection: close",
        "",
        ""
      ].join("\r\n"));
      socket.write(body.subarray(0, splitIndex), () => {
        setImmediate(() => socket.write(body.subarray(splitIndex)));
      });
    });
  });
}

function decodeRawResponse(response) {
  const separator = Buffer.from("\r\n\r\n");
  const headerEnd = response.indexOf(separator);
  assert.notEqual(headerEnd, -1);
  const head = response.subarray(0, headerEnd).toString("utf8");
  const encodedBody = response.subarray(headerEnd + separator.length);
  if (!/^transfer-encoding:\s*chunked$/im.test(head)) {
    return { head, body: encodedBody };
  }

  const chunks = [];
  let offset = 0;
  while (offset < encodedBody.length) {
    const lineEnd = encodedBody.indexOf(Buffer.from("\r\n"), offset);
    assert.notEqual(lineEnd, -1);
    const size = Number.parseInt(encodedBody.subarray(offset, lineEnd).toString("ascii"), 16);
    assert.ok(Number.isSafeInteger(size));
    offset = lineEnd + 2;
    if (size === 0) {
      break;
    }
    chunks.push(encodedBody.subarray(offset, offset + size));
    offset += size + 2;
  }
  return { head, body: Buffer.concat(chunks) };
}

async function waitFor(condition) {
  const deadline = Date.now() + 2000;
  while (Date.now() < deadline) {
    if (condition()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail("Timed out waiting for condition");
}

async function waitForStatus(url, token, expectedStatus) {
  const deadline = Date.now() + 2000;
  let lastBody;
  while (Date.now() < deadline) {
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` }
    });
    assert.equal(response.status, 200);
    lastBody = await response.json();
    if (lastBody.status === expectedStatus) {
      return lastBody;
    }
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  assert.fail(`Timed out waiting for ${expectedStatus}; last status was ${lastBody?.status}`);
}
