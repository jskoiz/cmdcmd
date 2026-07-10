import { logError, logInfo } from "./logger.js";
import { validateCapturePayload } from "./payload.js";
import { persistCapture } from "./storage.js";

export async function deliverPayload(payload, options) {
  const logger = options.logger ?? console;
  const requestId = options.requestId ?? null;
  const deliveryStatusStore = options.deliveryStatusStore ?? null;

  logInfo(logger, "capture.payload.validating", { requestId });
  const capture = validateCapturePayload(payload);

  logInfo(logger, "capture.payload.validated", {
    requestId,
    captureId: capture.captureId,
    source: capture.source,
    imageBytes: capture.imageBuffer.length,
    recognizedTextChars: capture.recognizedText.length,
    contextChars: capture.context.length
  });

  logInfo(logger, "capture.storage.persisting", {
    requestId,
    captureId: capture.captureId,
    inboxDir: options.config.inboxDir
  });
  const stored = await persistCapture(capture, options.config.inboxDir);
  logInfo(logger, "capture.storage.persisted", {
    requestId,
    captureId: capture.captureId,
    imagePath: stored.imagePath,
    metadataPath: stored.metadataPath
  });
  deliveryStatusStore?.accept(capture, stored, requestId);

  const delivery = () => deliverCaptureToDesktop(capture, stored, {
    codexClient: options.codexClient,
    deliveryStatusStore,
    logger,
    requestId
  });
  void options.deliveryQueue.enqueue(delivery);

  return {
    status: "accepted",
    captureId: capture.captureId,
    imagePath: stored.imagePath,
    metadataPath: stored.metadataPath,
    statusUrl: `/v1/captures/${encodeURIComponent(capture.captureId)}/status`
  };
}

export function createDeliveryQueue() {
  let tail = Promise.resolve();

  return {
    enqueue(delivery) {
      const result = tail.then(delivery, delivery);
      tail = result.catch(() => {});
      return result;
    }
  };
}

async function deliverCaptureToDesktop(capture, stored, options) {
  const logger = options.logger ?? console;
  const requestId = options.requestId ?? null;
  const codexStartedAt = Date.now();
  options.deliveryStatusStore?.deliver(capture.captureId);
  logInfo(logger, "capture.codex.delivery_started", {
    requestId,
    captureId: capture.captureId
  });

  try {
    const delivery = await options.codexClient.deliver(capture, stored);
    options.deliveryStatusStore?.complete(capture.captureId, delivery);
    logInfo(logger, "capture.codex.delivery_completed", {
      requestId,
      captureId: capture.captureId,
      status: delivery.status,
      deliveryLane: delivery.deliveryLane ?? null,
      durationMs: Date.now() - codexStartedAt
    });
  } catch (error) {
    options.deliveryStatusStore?.fail(capture.captureId, error);
    logError(logger, "capture.codex.delivery_failed", {
      requestId,
      captureId: capture.captureId,
      message: error.message,
      stack: error.stack,
      durationMs: Date.now() - codexStartedAt
    });
  }
}
