export function logInfo(logger, event, fields = {}) {
  writeLog(logger, "info", event, fields);
}

export function logError(logger, event, fields = {}) {
  writeLog(logger, "error", event, fields);
}

function writeLog(logger, level, event, fields) {
  const payload = {
    time: new Date().toISOString(),
    level,
    event,
    ...fields
  };
  const line = JSON.stringify(payload);

  if (level === "error" && typeof logger?.error === "function") {
    logger.error(line);
    return;
  }

  if (typeof logger?.info === "function") {
    logger.info(line);
    return;
  }

  if (typeof logger?.log === "function") {
    logger.log(line);
  }
}
