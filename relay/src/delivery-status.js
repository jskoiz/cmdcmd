const MAX_STATUSES = 200;

export function createDeliveryStatusStore(options = {}) {
  const now = options.now ?? (() => new Date());
  const statuses = new Map();

  return {
    accept(capture, stored, requestId, deliveryMode = "app-server") {
      return write(capture.captureId, {
        status: "accepted",
        message: queuedMessage(capture, deliveryMode),
        deliveryMode,
        requestId,
        imagePath: stored.imagePath,
        metadataPath: stored.metadataPath,
        acceptedAt: nowIso(now)
      });
    },

    deliver(captureId, deliveryMode = "app-server") {
      return write(captureId, {
        status: "delivering",
        message: deliveringMessage(deliveryMode),
        deliveryMode
      });
    },

    complete(captureId, delivery) {
      return write(captureId, {
        status: "delivered",
        message: delivery.message ?? deliveredMessage(delivery.deliveryLane),
        threadId: delivery.threadId ?? null,
        turnId: delivery.turnId ?? null,
        turnStatus: delivery.turnStatus ?? null,
        deliveryLane: delivery.deliveryLane ?? null
      });
    },

    fail(captureId, error) {
      const previous = statuses.get(captureId);
      const prefix =
        previous?.deliveryMode === "desktop-appshot"
          ? "Desktop Appshot failed"
          : "Codex delivery failed";
      return write(captureId, {
        status: "failed",
        message: `${prefix}: ${truncate(error.message)}`,
        error: truncate(error.message)
      });
    },

    get(captureId) {
      const status = statuses.get(captureId);
      return status ? { ...status } : null;
    }
  };

  function write(captureId, patch) {
    const previous = statuses.get(captureId) ?? {
      captureId,
      acceptedAt: nowIso(now)
    };
    const status = {
      ...previous,
      ...patch,
      captureId,
      updatedAt: nowIso(now)
    };
    statuses.set(captureId, status);
    pruneOldest(statuses);
    return { ...status };
  }
}

function queuedMessage(capture, deliveryMode) {
  if (deliveryMode === "desktop-appshot") {
    return "Queued for Desktop Appshot";
  }
  return capture.threadHint ? "Queued to Codex thread" : "Queued in Codex";
}

function deliveringMessage(deliveryMode) {
  return deliveryMode === "desktop-appshot"
    ? "Triggering Desktop Appshot"
    : "Sending to Codex thread";
}

function deliveredMessage(deliveryLane) {
  return deliveryLane === "desktop-appshot"
    ? "Triggered Desktop Appshot"
    : "Delivered to Codex thread";
}

function nowIso(now) {
  return now().toISOString();
}

function truncate(value, maxLength = 220) {
  if (!value) {
    return "Unknown error";
  }
  return value.length > maxLength ? `${value.slice(0, maxLength - 1)}…` : value;
}

function pruneOldest(statuses) {
  while (statuses.size > MAX_STATUSES) {
    const oldestKey = statuses.keys().next().value;
    statuses.delete(oldestKey);
  }
}
