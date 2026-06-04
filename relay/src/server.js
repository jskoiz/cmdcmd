import http from "node:http";
import { isAuthorized } from "./auth.js";
import { createDeliveryStatusStore } from "./delivery-status.js";
import { logError, logInfo } from "./logger.js";
import { deliverPayload } from "./relay.js";

export function createServer({ config, codexClient, logger = console }) {
  const deliveryStatusStore = createDeliveryStatusStore();

  return http.createServer(async (request, response) => {
    const requestId = createRequestId();
    const startedAt = Date.now();
    const requestUrl = new URL(request.url ?? "/", "http://127.0.0.1");

    try {
      if (request.method === "GET" && requestUrl.pathname === "/healthz") {
        return sendJson(response, 200, { status: "ok" });
      }

      if (!isAuthorized(request.headers, config.token)) {
        logInfo(logger, "capture.request.unauthorized", {
          requestId,
          path: requestUrl.pathname,
          durationMs: Date.now() - startedAt
        });
        return sendJson(response, 401, { error: "Unauthorized." });
      }

      if (request.method === "GET") {
        const captureId = parseStatusPath(requestUrl.pathname);
        if (!captureId) {
          return sendJson(response, 404, { error: "Not found." });
        }

        const status = deliveryStatusStore.get(captureId);
        if (!status) {
          return sendJson(response, 404, { error: "Capture status not found." });
        }

        return sendJson(response, 200, status);
      }

      if (request.method !== "POST" || requestUrl.pathname !== "/v1/captures") {
        return sendJson(response, 404, { error: "Not found." });
      }

      logInfo(logger, "capture.request.started", {
        requestId,
        remoteAddress: request.socket.remoteAddress,
        contentLength: request.headers["content-length"] ?? null
      });

      const { payload, bytes } = await readJsonBody(request, config.maxBodyBytes);
      logInfo(logger, "capture.request.body_read", {
        requestId,
        bytes,
        durationMs: Date.now() - startedAt
      });

      const result = await deliverPayload(payload, {
        config,
        codexClient,
        deliveryStatusStore,
        logger,
        requestId
      });
      logInfo(logger, "capture.request.completed", {
        requestId,
        captureId: result.captureId,
        status: result.status,
        threadId: result.threadId ?? null,
        durationMs: Date.now() - startedAt
      });
      return sendJson(response, result.status === "accepted" ? 202 : 200, result);
    } catch (error) {
      const statusCode = error.statusCode ?? 502;
      logError(logger, "capture.request.failed", {
        requestId,
        statusCode,
        message: error.message,
        stack: statusCode >= 500 ? error.stack : undefined,
        durationMs: Date.now() - startedAt
      });
      return sendJson(response, statusCode, { error: error.message });
    }
  });
}

function sendJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(`${JSON.stringify(body)}\n`);
}

function parseStatusPath(pathname) {
  const match = pathname.match(/^\/v1\/captures\/([^/]+)\/status$/);
  return match ? decodeURIComponent(match[1]) : null;
}

async function readJsonBody(request, maxBytes) {
  const contentType = request.headers["content-type"] ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    const error = new Error("Content-Type must be application/json.");
    error.statusCode = 415;
    throw error;
  }

  let body = "";
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > maxBytes) {
      const error = new Error("Request body is too large.");
      error.statusCode = 413;
      throw error;
    }
    body += chunk;
  }

  try {
    return { payload: JSON.parse(body), bytes };
  } catch {
    const error = new Error("Request body must be valid JSON.");
    error.statusCode = 400;
    throw error;
  }
}

function createRequestId() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}
