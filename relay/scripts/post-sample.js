import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnvFile } from "../src/env.js";

const relayRoot = fileURLToPath(new URL("..", import.meta.url));
loadEnvFile(path.join(relayRoot, ".env"));

const endpoint =
  process.env.CMDCMD_RELAY_URL ?? "http://127.0.0.1:8787/v1/captures";
const token = process.env.CMDCMD_RELAY_TOKEN;

if (!token) {
  console.error("CMDCMD_RELAY_TOKEN is required.");
  process.exit(1);
}

const payload = fs.readFileSync(
  path.join(relayRoot, "fixtures", "sample-payload.json"),
  "utf8"
);
const response = await fetch(endpoint, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json"
  },
  body: payload
});

const body = await response.text();
console.log(`HTTP ${response.status}`);
console.log(body.trim());

if (!response.ok) {
  process.exit(1);
}
