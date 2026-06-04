import path from "node:path";
import { fileURLToPath } from "node:url";
import { CodexAppServerClient, createDryRunClient } from "./app-server-client.js";
import { loadConfig } from "./config.js";
import { DesktopAppshotClient } from "./desktop-appshot-client.js";
import { loadEnvFile } from "./env.js";
import { createServer } from "./server.js";

const relayRoot = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = path.resolve(relayRoot, "..");

loadEnvFile(path.join(relayRoot, ".env"));

const config = loadConfig(process.env, {
  cwd: repoRoot,
  defaultCodexCwd: repoRoot
});
const codexClient = createDeliveryClient(config);
const server = createServer({ config, codexClient });

server.listen(config.port, config.host, () => {
  const mode = config.dryRun
    ? `dry-run/${config.deliveryMode}`
    : config.deliveryMode;
  console.log(
    `cmd+cmd relay listening on http://${config.host}:${config.port}/v1/captures (${mode})`
  );
});

function createDeliveryClient(config) {
  if (config.dryRun) {
    return createDryRunClient();
  }

  if (config.deliveryMode === "desktop-appshot") {
    return new DesktopAppshotClient(config);
  }

  return new CodexAppServerClient(config);
}
