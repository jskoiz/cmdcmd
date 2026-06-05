const ALLOWED_IMAGE_TYPES = new Set(["image/png", "image/jpeg"]);
const ALLOWED_PAYLOAD_FIELDS = new Set([
  "schemaVersion",
  "captureId",
  "createdAt",
  "source",
  "sourceDetail",
  "context",
  "recognizedText",
  "imageFilename",
  "imageMimeType",
  "imageBase64"
]);
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

  if (payload.schemaVersion !== 1) {
    throw new PayloadValidationError("schemaVersion must be 1.");
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
    schemaVersion: 1,
    captureId,
    createdAt,
    source: requiredString(payload.source, "source"),
    sourceDetail: optionalString(payload.sourceDetail),
    context: optionalString(payload.context),
    recognizedText: optionalString(payload.recognizedText),
    imageFilename: requiredString(payload.imageFilename, "imageFilename"),
    imageMimeType,
    imageBuffer
  };
}

function rejectUnsupportedFields(payload) {
  const unsupported = Object.keys(payload).filter(
    (key) => !ALLOWED_PAYLOAD_FIELDS.has(key)
  );
  if (unsupported.length > 0) {
    throw new PayloadValidationError(
      `Unsupported payload field: ${unsupported[0]}.`
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
