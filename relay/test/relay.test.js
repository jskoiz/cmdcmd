import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { loadConfig } from "../src/config.js";
import {
  buildDesktopAttachmentText,
  buildDesktopHelperArgs,
  DesktopAppshotClient
} from "../src/desktop-appshot-client.js";
import { createDeliveryStatusStore } from "../src/delivery-status.js";
import { deliverPayload } from "../src/relay.js";
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
    deliveryStatusStore: createDeliveryStatusStore(),
    codexClient: {
      async deliver(capture, stored) {
        calls.push({ capture, stored });
        resolveDelivery();
        return {
          status: "delivered",
          deliveryLane: "desktop-appshot",
          message: "AppShot sent to Codex"
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

test("loadConfig includes Codex Desktop paste defaults", () => {
  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret"
    },
    { cwd: process.cwd() }
  );

  assert.equal(config.appshot.openImageInViewer, false);
  assert.equal(config.appshot.viewerBundle, "com.apple.Preview");
  assert.equal(config.appshot.closeViewerWindow, true);
  assert.equal(config.appshot.codexBundle, "com.openai.codex");
  assert.equal(config.appshot.pasteDelayMs, 400);
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

test("DesktopAppshotClient opens the screenshot hidden when viewer is enabled", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmdcmd-appshot-"));
  const imagePath = path.join(tempDir, "image.png");
  await fs.writeFile(imagePath, Buffer.from(samplePayload.imageBase64, "base64"));
  const commands = [];

  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: tempDir,
      CMDCMD_APPSHOT_OPEN_VIEWER: "true",
      CMDCMD_APPSHOT_VIEWER_BUNDLE: "com.apple.Preview",
      CMDCMD_APPSHOT_CODEX_BUNDLE: "com.openai.codex",
      CMDCMD_APPSHOT_OPEN_DELAY_MS: "1",
      CMDCMD_APPSHOT_PASTE_DELAY_MS: "1",
      CMDCMD_APPSHOT_CLOSE_VIEWER: "true"
    },
    { cwd: tempDir }
  );
  const client = new DesktopAppshotClient(config, {
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
  assert.equal(result.deliveryLane, "desktop-appshot");
  assert.equal(
    result.message,
    "AppShot sent to Codex"
  );
  assert.equal(result.targetBundle, "com.openai.codex");
  const textPath = path.join(tempDir, "metadata.txt");
  assert.equal(
    await fs.readFile(textPath, "utf8"),
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
    ["/usr/bin/open", "-g"],
    ["/tmp/cmdcmd-desktop-helper", "--image-path"]
  ]);
  assert.deepEqual(commands[0].args, [
    "-g",
    "-j",
    "-b",
    "com.apple.Preview",
    imagePath
  ]);
  assert.deepEqual(commands[1].args, [
    "--image-path",
    imagePath,
    "--codex-bundle",
    "com.openai.codex",
    "--focus-delay-ms",
    "1",
    "--composer-bottom-offset",
    "70",
    "--text-path",
    textPath,
    "--viewer-bundle",
    "com.apple.Preview",
    "--close-viewer"
  ]);
});

test("DesktopAppshotClient pastes without opening Preview by default", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "cmdcmd-appshot-"));
  const imagePath = path.join(tempDir, "image.png");
  await fs.writeFile(imagePath, Buffer.from(samplePayload.imageBase64, "base64"));
  const commands = [];

  const config = loadConfig(
    {
      CMDCMD_RELAY_TOKEN: "secret",
      CMDCMD_INBOX_DIR: tempDir,
      CMDCMD_APPSHOT_CODEX_BUNDLE: "com.openai.codex",
      CMDCMD_APPSHOT_PASTE_DELAY_MS: "1"
    },
    { cwd: tempDir }
  );
  const client = new DesktopAppshotClient(config, {
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
});

test("buildDesktopHelperArgs configures frontmost composer paste", () => {
  assert.deepEqual(
    buildDesktopHelperArgs(
      "/tmp/screenshot.png",
      {
        codexBundle: "com.openai.codex",
        pasteDelayMs: 250,
        openImageInViewer: true,
        closeViewerWindow: true,
        viewerBundle: "com.apple.Preview"
      },
      { textPath: "/tmp/screenshot.txt" }
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
      "--text-path",
      "/tmp/screenshot.txt",
      "--viewer-bundle",
      "com.apple.Preview",
      "--close-viewer"
    ]
  );
});

test("buildDesktopAttachmentText includes context and OCR", () => {
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
    "OCR text:\nVisible text"
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
      "CodexShot",
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
      "OCR: 5 useful lines, 59 characters, 412 ms, avg confidence 89%",
      "",
      "OCR text:",
      "CodexShot",
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
  assert.equal(accepted.message, "AppShot queued for Codex");

  const delivering = store.deliver(capture.captureId);
  assert.equal(delivering.message, "Sending AppShot to Codex");

  const delivered = store.complete(capture.captureId, {
    deliveryLane: "desktop-appshot"
  });
  assert.equal(
    delivered.message,
    "AppShot sent to Codex"
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
          deliveryLane: "desktop-appshot",
          message: "AppShot sent to Codex"
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
          deliveryLane: "desktop-appshot",
          message: "AppShot sent to Codex"
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
    "AppShot sent to Codex"
  );
  assert.equal(deliveredBody.deliveryLane, "desktop-appshot");
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
