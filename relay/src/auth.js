import crypto from "node:crypto";

export function isAuthorized(headers, expectedToken) {
  const header = headers.authorization ?? headers.Authorization ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) {
    return false;
  }
  return timingSafeEqual(match[1].trim(), expectedToken);
}

function timingSafeEqual(actual, expected) {
  const actualBuffer = Buffer.from(actual);
  const expectedBuffer = Buffer.from(expected);

  if (actualBuffer.length !== expectedBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}
