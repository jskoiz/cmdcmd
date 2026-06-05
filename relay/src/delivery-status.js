const MAX_STATUSES = 200;

export function createDeliveryStatusStore(options = {}) {
  const now = options.now ?? (() => new Date());
  const statuses = new Map();

  return {
    accept(capture, stored, requestId) {
      return write(capture.captureId, {
        status: "accepted",
        message: "AppShot queued for Codex",
        requestId,
        imagePath: stored.imagePath,
        metadataPath: stored.metadataPath,
        acceptedAt: nowIso(now)
      });
    },

    deliver(captureId) {
      return write(captureId, {
        status: "delivering",
        message: "Sending AppShot to Codex"
      });
    },

    complete(captureId, delivery) {
      return write(captureId, {
        status: "delivered",
        message:
          delivery.message ??
          "AppShot sent to Codex",
        deliveryLane: delivery.deliveryLane ?? null
      });
    },

    fail(captureId, error) {
      return write(captureId, {
        status: "failed",
        message: `Could not send AppShot: ${truncate(error.message)}`,
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
