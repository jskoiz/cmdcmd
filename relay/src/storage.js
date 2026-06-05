import fs from "node:fs/promises";
import path from "node:path";

const EXTENSION_BY_MIME = {
  "image/png": ".png",
  "image/jpeg": ".jpg"
};

export async function persistCapture(capture, inboxDir) {
  const date = capture.createdAt.slice(0, 10);
  const targetDir = path.join(inboxDir, date);
  await fs.mkdir(targetDir, { recursive: true, mode: 0o700 });

  const baseName = safeBaseName(capture.imageFilename, capture.imageMimeType);
  const stem = `${capture.createdAt.replaceAll(":", "-")}-${capture.captureId}`;
  const imagePath = await nextAvailablePath(
    path.join(targetDir, `${stem}-${baseName}`)
  );
  const metadataPath = await nextAvailablePath(path.join(targetDir, `${stem}.json`));

  await fs.writeFile(imagePath, capture.imageBuffer, { flag: "wx", mode: 0o600 });
  await fs.writeFile(
    metadataPath,
    `${JSON.stringify(metadataFor(capture, imagePath), null, 2)}\n`,
    { flag: "wx", mode: 0o600 }
  );

  return { imagePath, metadataPath };
}

function metadataFor(capture, imagePath) {
  return {
    schemaVersion: capture.schemaVersion,
    captureId: capture.captureId,
    createdAt: capture.createdAt,
    source: capture.source,
    sourceDetail: capture.sourceDetail,
    screenshotContext: capture.screenshotContext,
    context: capture.context,
    recognizedText: capture.recognizedText,
    imageFilename: capture.imageFilename,
    imageMimeType: capture.imageMimeType,
    imagePath
  };
}

function safeBaseName(filename, mimeType) {
  const parsed = path.parse(path.basename(filename));
  const stem = (parsed.name || "screenshot")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
  const extension = EXTENSION_BY_MIME[mimeType];
  return `${stem || "screenshot"}${extension}`;
}

async function nextAvailablePath(targetPath) {
  if (!(await exists(targetPath))) {
    return targetPath;
  }

  const parsed = path.parse(targetPath);
  for (let index = 1; index < 1000; index += 1) {
    const candidate = path.join(
      parsed.dir,
      `${parsed.name}-${index}${parsed.ext}`
    );
    if (!(await exists(candidate))) {
      return candidate;
    }
  }

  throw new Error(`Unable to find an unused path for ${targetPath}`);
}

async function exists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}
