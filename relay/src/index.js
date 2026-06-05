import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig } from "./config.js";
import { DesktopAppshotClient } from "./desktop-appshot-client.js";
import { loadEnvFile } from "./env.js";
import { createServer } from "./server.js";

const relayRoot = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = path.resolve(relayRoot, "..");

loadEnvFile(path.join(relayRoot, ".env"));

const config = loadConfig(process.env, {
  cwd: repoRoot
});
const codexClient = new DesktopAppshotClient(config);
const server = createServer({ config, codexClient });

server.listen(config.port, config.host, () => {
  console.log(
    `cmd+cmd relay listening on http://${config.host}:${config.port}/v1/captures (desktop-appshot)`
  );
});
