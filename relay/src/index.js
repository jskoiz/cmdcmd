import path from "node:path";
import { fileURLToPath } from "node:url";
import { CodexAppServerClient, createDryRunClient } from "./app-server-client.js";
import { loadConfig } from "./config.js";
import { loadEnvFile } from "./env.js";
import { createServer } from "./server.js";

const relayRoot = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = path.resolve(relayRoot, "..");

loadEnvFile(path.join(relayRoot, ".env"));

const config = loadConfig(process.env, {
  cwd: repoRoot,
  defaultCodexCwd: repoRoot
});
const codexClient = config.dryRun
  ? createDryRunClient()
  : new CodexAppServerClient(config);
const server = createServer({ config, codexClient });

server.listen(config.port, config.host, () => {
  const mode = config.dryRun ? "dry-run" : "codex-app-server";
  console.log(
    `cmd+cmd relay listening on http://${config.host}:${config.port}/v1/captures (${mode})`
  );
});
