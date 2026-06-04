export function buildCodexPrompt(capture, stored) {
  const sections = [
    "A screenshot was sent from cmd+cmd.",
    [
      "Capture details:",
      `- captureId: ${capture.captureId}`,
      `- createdAt: ${capture.createdAt}`,
      `- source: ${capture.source}${capture.sourceDetail ? ` (${capture.sourceDetail})` : ""}`,
      `- image: ${stored.imagePath}`,
      `- metadata: ${stored.metadataPath}`
    ].join("\n")
  ];

  if (capture.threadHint) {
    sections.push(`Requested thread hint: ${capture.threadHint}`);
  }

  if (capture.context) {
    sections.push(`User context:\n${capture.context}`);
  }

  if (capture.recognizedText) {
    sections.push(`OCR text:\n${capture.recognizedText}`);
  }

  sections.push(
    "Inspect the screenshot and the supplied context. If the context asks for a task, act on it. If it is ambiguous, summarize the useful observations and ask what should happen next."
  );

  return sections.join("\n\n");
}
