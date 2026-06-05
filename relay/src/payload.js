const ALLOWED_IMAGE_TYPES = new Set(["image/png", "image/jpeg"]);
const ALLOWED_PAYLOAD_FIELDS = new Set([
  "schemaVersion",
  "captureId",
  "createdAt",
  "source",
  "sourceDetail",
  "screenshotContext",
  "context",
  "recognizedText",
  "imageFilename",
  "imageMimeType",
  "imageBase64"
]);
const ALLOWED_SCREENSHOT_CONTEXT_FIELDS = new Set([
  "capturedAt",
  "preparedAt",
  "timeZoneIdentifier",
  "source",
  "sourceDetail",
  "imageFilename",
  "imageMimeType",
  "pixelWidth",
  "pixelHeight",
  "originalImageBytes",
  "uploadImageBytes",
  "ocrEnabled",
  "ocrDurationMs",
  "ocrLineCount",
  "ocrCharacterCount",
  "ocrTimedOut",
  "ocrAverageConfidence",
  "visibleApp"
]);
const ALLOWED_VISIBLE_APP_FIELDS = new Set(["name", "confidence", "evidence"]);
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class PayloadValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "PayloadValidationError";
    this.statusCode = 400;
  }
}

export function validateCapturePayload(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new PayloadValidationError("Request body must be a JSON object.");
  }
  rejectUnsupportedFields(payload);

  if (payload.schemaVersion !== 2) {
    throw new PayloadValidationError("schemaVersion must be 2.");
  }

  const captureId = requiredString(payload.captureId, "captureId");
  if (!UUID_PATTERN.test(captureId)) {
    throw new PayloadValidationError("captureId must be a UUID string.");
  }

  const createdAt = requiredString(payload.createdAt, "createdAt");
  if (Number.isNaN(Date.parse(createdAt))) {
    throw new PayloadValidationError("createdAt must be an ISO date string.");
  }

  const imageMimeType = requiredString(payload.imageMimeType, "imageMimeType");
  if (!ALLOWED_IMAGE_TYPES.has(imageMimeType)) {
    throw new PayloadValidationError(
      "imageMimeType must be image/png or image/jpeg."
    );
  }

  const imageBase64 = requiredString(payload.imageBase64, "imageBase64");
  const imageBuffer = decodeBase64(imageBase64);
  if (imageBuffer.length === 0) {
    throw new PayloadValidationError("imageBase64 decoded to an empty file.");
  }

  return {
    schemaVersion: 2,
    captureId,
    createdAt,
    source: requiredString(payload.source, "source"),
    sourceDetail: optionalString(payload.sourceDetail),
    screenshotContext: normalizeScreenshotContext(
      requiredObject(payload.screenshotContext, "screenshotContext")
    ),
    context: optionalString(payload.context),
    recognizedText: optionalString(payload.recognizedText),
    imageFilename: requiredString(payload.imageFilename, "imageFilename"),
    imageMimeType,
    imageBuffer
  };
}

function normalizeScreenshotContext(value) {
  rejectUnsupportedFields(
    value,
    ALLOWED_SCREENSHOT_CONTEXT_FIELDS,
    "screenshotContext"
  );

  return {
    capturedAt: optionalDateString(value.capturedAt, "screenshotContext.capturedAt"),
    preparedAt: requiredDateString(value.preparedAt, "screenshotContext.preparedAt"),
    timeZoneIdentifier: optionalString(value.timeZoneIdentifier),
    source: requiredString(value.source, "screenshotContext.source"),
    sourceDetail: optionalString(value.sourceDetail),
    imageFilename: requiredString(value.imageFilename, "screenshotContext.imageFilename"),
    imageMimeType: requiredString(value.imageMimeType, "screenshotContext.imageMimeType"),
    pixelWidth: optionalPositiveInteger(value.pixelWidth, "screenshotContext.pixelWidth"),
    pixelHeight: optionalPositiveInteger(value.pixelHeight, "screenshotContext.pixelHeight"),
    originalImageBytes: requiredNonNegativeInteger(
      value.originalImageBytes,
      "screenshotContext.originalImageBytes"
    ),
    uploadImageBytes: requiredNonNegativeInteger(
      value.uploadImageBytes,
      "screenshotContext.uploadImageBytes"
    ),
    ocrEnabled: requiredBoolean(value.ocrEnabled, "screenshotContext.ocrEnabled"),
    ocrDurationMs: optionalNonNegativeInteger(
      value.ocrDurationMs,
      "screenshotContext.ocrDurationMs"
    ),
    ocrLineCount: requiredNonNegativeInteger(
      value.ocrLineCount,
      "screenshotContext.ocrLineCount"
    ),
    ocrCharacterCount: requiredNonNegativeInteger(
      value.ocrCharacterCount,
      "screenshotContext.ocrCharacterCount"
    ),
    ocrTimedOut: requiredBoolean(value.ocrTimedOut, "screenshotContext.ocrTimedOut"),
    ocrAverageConfidence: optionalUnitNumber(
      value.ocrAverageConfidence,
      "screenshotContext.ocrAverageConfidence"
    ),
    visibleApp: normalizeVisibleApp(value.visibleApp)
  };
}

function normalizeVisibleApp(value) {
  if (value === undefined || value === null) {
    return null;
  }

  const app = requiredObject(value, "screenshotContext.visibleApp");
  rejectUnsupportedFields(
    app,
    ALLOWED_VISIBLE_APP_FIELDS,
    "screenshotContext.visibleApp"
  );
  return {
    name: requiredString(app.name, "screenshotContext.visibleApp.name"),
    confidence: requiredString(
      app.confidence,
      "screenshotContext.visibleApp.confidence"
    ),
    evidence: optionalStringArray(
      app.evidence,
      "screenshotContext.visibleApp.evidence"
    )
  };
}

function rejectUnsupportedFields(
  payload,
  allowedFields = ALLOWED_PAYLOAD_FIELDS,
  fieldLabel = "payload"
) {
  const unsupported = Object.keys(payload).filter(
    (key) => !allowedFields.has(key)
  );
  if (unsupported.length > 0) {
    throw new PayloadValidationError(
      `Unsupported ${fieldLabel} field: ${unsupported[0]}.`
    );
  }
}

function requiredString(value, field) {
  if (typeof value !== "string" || !value.trim()) {
    throw new PayloadValidationError(`${field} is required.`);
  }
  return value.trim();
}

function optionalString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function requiredObject(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new PayloadValidationError(`${field} is required.`);
  }
  return value;
}

function requiredDateString(value, field) {
  const date = requiredString(value, field);
  if (Number.isNaN(Date.parse(date))) {
    throw new PayloadValidationError(`${field} must be an ISO date string.`);
  }
  return date;
}

function optionalDateString(value, field) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  return requiredDateString(value, field);
}

function requiredBoolean(value, field) {
  if (typeof value !== "boolean") {
    throw new PayloadValidationError(`${field} must be a boolean.`);
  }
  return value;
}

function requiredNonNegativeInteger(value, field) {
  if (!Number.isInteger(value) || value < 0) {
    throw new PayloadValidationError(`${field} must be a non-negative integer.`);
  }
  return value;
}

function optionalNonNegativeInteger(value, field) {
  if (value === undefined || value === null) {
    return null;
  }
  return requiredNonNegativeInteger(value, field);
}

function optionalPositiveInteger(value, field) {
  if (value === undefined || value === null) {
    return null;
  }
  if (!Number.isInteger(value) || value <= 0) {
    throw new PayloadValidationError(`${field} must be a positive integer.`);
  }
  return value;
}

function optionalUnitNumber(value, field) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "number" || value < 0 || value > 1) {
    throw new PayloadValidationError(`${field} must be between 0 and 1.`);
  }
  return value;
}

function optionalStringArray(value, field) {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new PayloadValidationError(`${field} must be an array.`);
  }
  return value
    .map((item, index) => {
      if (typeof item !== "string") {
        throw new PayloadValidationError(`${field}[${index}] must be a string.`);
      }
      return item.trim();
    })
    .filter(Boolean);
}

function decodeBase64(value) {
  if (!/^[A-Za-z0-9+/=\s_-]+$/.test(value)) {
    throw new PayloadValidationError("imageBase64 is not valid base64.");
  }

  try {
    return Buffer.from(value, "base64");
  } catch {
    throw new PayloadValidationError("imageBase64 is not valid base64.");
  }
}
