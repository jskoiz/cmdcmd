import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { buildTurnInput, sandboxModeToPolicy } from "../src/app-server-client.js";
import { loadConfig } from "../src/config.js";
import { createDeliveryStatusStore } from "../src/delivery-status.js";
import { buildCodexPrompt } from "../src/prompt.js";
import { deliverPayload } from "../src/relay.js";
import { createServer } from "../src/server.js";

const samplePayload = {
  schemaVersion: 1,
  captureId: "22222222-2222-4222-8222-222222222222",
  createdAt: "2026-06-04T12:00:00.000Z",
  source: "shortcut",
  sourceDetail: "Unit test",
  context: "Please review the screenshot.",
  recognizedText: "OCR from screenshot",
  threadHint: "",
  imageFilename: "../unsafe name.png",
  imageMimeType: "image/png",
  imageBase64:
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAACKADAAQAAAABAAAACAAAAACVhHtSAAAAGklEQVQIHWMW2Nkoy776XwcPGsnEgAMMTgkAzi8JTigyXpYAAAAASUVORK5CYII="
};

test("deliverPayload validates, stores, and queues the Codex client", async () => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "codexshot-relay-"));
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
          threadId: "thr_test",
          finalResponse: "ok",
          usage: null
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
  assert.equal(metadata.imagePath, result.imagePath);
});

test("deliverPayload uses the configured default thread when the payload omits one", async () => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "codexshot-relay-"));
  let deliveredThreadHint = "";
  let resolveDelivery;
  const deliveryStarted = new Promise((resolve) => {
    resolveDelivery = resolve;
  });

  const result = await deliverPayload(samplePayload, {
    config: {
      inboxDir,
      codex: {
        defaultThreadHint: "019e945a-df22-79a0-977d-5c25eb11ba43"
      }
    },
    deliveryStatusStore: createDeliveryStatusStore(),
    codexClient: {
      async deliver(capture) {
        deliveredThreadHint = capture.threadHint;
        resolveDelivery();
        return {
          status: "delivered",
          threadId: capture.threadHint,
          finalResponse: "ok",
          usage: null
        };
      }
    }
  });

  assert.equal(result.status, "accepted");
  await deliveryStarted;
  assert.equal(deliveredThreadHint, "019e945a-df22-79a0-977d-5c25eb11ba43");
});

test("buildCodexPrompt includes the stored screenshot and OCR context", () => {
  const prompt = buildCodexPrompt(
    {
      ...samplePayload,
      imageBuffer: Buffer.from("x")
    },
    {
      imagePath: "/tmp/codexshot/sample.png",
      metadataPath: "/tmp/codexshot/sample.json"
    }
  );

  assert.match(prompt, /A screenshot was sent from CodexShot/);
  assert.match(prompt, /\/tmp\/codexshot\/sample\.png/);
  assert.match(prompt, /Please review the screenshot/);
  assert.match(prompt, /OCR from screenshot/);
});

test("buildTurnInput sends the screenshot as a native local image", () => {
  const input = buildTurnInput(
    {
      ...samplePayload,
      imageBuffer: Buffer.from("x")
    },
    {
      imagePath: "/tmp/codexshot/sample.png",
      metadataPath: "/tmp/codexshot/sample.json"
    }
  );

  assert.equal(input.length, 2);
  assert.equal(input[0].type, "text");
  assert.equal(input[0].text_elements.length, 0);
  assert.match(input[0].text, /A screenshot was sent from CodexShot/);
  assert.deepEqual(input[1], {
    type: "localImage",
    path: "/tmp/codexshot/sample.png",
    detail: "high"
  });
});

test("sandboxModeToPolicy maps relay sandbox settings to app-server policy", () => {
  assert.deepEqual(sandboxModeToPolicy("read-only"), {
    type: "readOnly",
    networkAccess: false
  });
  assert.deepEqual(sandboxModeToPolicy("danger-full-access"), {
    type: "dangerFullAccess"
  });
});

test("createServer requires bearer auth for capture posts", async () => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "codexshot-relay-"));
  const config = loadConfig(
    {
      CODEXSHOT_RELAY_TOKEN: "secret",
      CODEXSHOT_INBOX_DIR: inboxDir
    },
    { cwd: process.cwd() }
  );
  const server = createServer({
    config,
    codexClient: {
      async deliver() {
        return {
          status: "delivered",
          threadId: "thr_test",
          finalResponse: "ok",
          usage: null
        };
      }
    },
    logger: { error() {} }
  });

  await listen(server);
  after(() => server.close());

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

test("createServer exposes authenticated delivery status until completion", async () => {
  const inboxDir = await fs.mkdtemp(path.join(os.tmpdir(), "codexshot-relay-"));
  const config = loadConfig(
    {
      CODEXSHOT_RELAY_TOKEN: "secret",
      CODEXSHOT_INBOX_DIR: inboxDir
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
          threadId: "019e945a-df22-79a0-977d-5c25eb11ba43",
          turnId: "turn_test",
          turnStatus: "completed",
          deliveryLane: "app-server-turn",
          finalResponse: null,
          usage: null
        };
      }
    },
    logger: { error() {} }
  });

  await listen(server);
  after(() => server.close());

  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const postResponse = await fetch(`${baseUrl}/v1/captures`, {
    method: "POST",
    headers: {
      Authorization: "Bearer secret",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      ...samplePayload,
      captureId: "44444444-4444-4444-8444-444444444444",
      threadHint: "019e945a-df22-79a0-977d-5c25eb11ba43"
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
  assert.equal(deliveredBody.message, "Delivered to Codex thread");
  assert.equal(deliveredBody.threadId, "019e945a-df22-79a0-977d-5c25eb11ba43");
  assert.equal(deliveredBody.turnId, "turn_test");
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
