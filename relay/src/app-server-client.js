import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { logError, logInfo } from "./logger.js";
import { buildCodexPrompt } from "./prompt.js";

export class CodexAppServerClient {
  constructor(config, options = {}) {
    this.config = config;
    this.processFactory = options.processFactory ?? defaultProcessFactory;
    this.logger = options.logger ?? console;
  }

  async deliver(capture, stored) {
    const session = new AppServerSession({
      binaryPath: this.config.codex.binaryPath,
      processFactory: this.processFactory,
      requestTimeoutMs: this.config.codex.requestTimeoutMs,
      logger: this.logger
    });

    const startedAt = Date.now();
    logInfo(this.logger, "codex.app_server.delivery_started", {
      captureId: capture.captureId,
      binaryPath: this.config.codex.binaryPath
    });

    try {
      await session.start();
      const thread = await this.openThread(session, capture);
      const input = buildTurnInput(capture, stored);
      const activeTurnId = findActiveTurnId(thread);
      const turn = activeTurnId
        ? await session.request("turn/steer", {
            threadId: thread.id,
            expectedTurnId: activeTurnId,
            input,
            clientUserMessageId: capture.captureId
          })
        : await session.request("turn/start", {
            threadId: thread.id,
            clientUserMessageId: capture.captureId,
            input,
            cwd: this.config.codex.workingDirectory,
            approvalPolicy: this.config.codex.approvalPolicy,
            sandboxPolicy: sandboxModeToPolicy(this.config.codex.sandboxMode),
            model: this.config.codex.model ?? null,
            serviceTier: null,
            effort: null,
            summary: null,
            personality: null,
            outputSchema: null
          });

      const turnId = activeTurnId ?? turn.turn?.id ?? turn.turnId;
      if (!turnId) {
        throw new Error("Codex app-server did not return a turn id.");
      }

      logInfo(this.logger, "codex.app_server.turn_started", {
        captureId: capture.captureId,
        threadId: thread.id,
        turnId,
        mode: activeTurnId ? "steer" : "start"
      });

      const completedTurn = await session.waitForTurnCompletion(
        thread.id,
        turnId,
        this.config.codex.turnTimeoutMs
      );

      logInfo(this.logger, "codex.app_server.delivery_completed", {
        captureId: capture.captureId,
        threadId: thread.id,
        turnId,
        turnStatus: completedTurn.status,
        durationMs: Date.now() - startedAt
      });

      return {
        status: "delivered",
        threadId: thread.id,
        turnId,
        turnStatus: completedTurn.status,
        deliveryLane: "app-server-turn",
        finalResponse: null,
        usage: null
      };
    } finally {
      session.close();
    }
  }

  async openThread(session, capture) {
    const common = {
      cwd: this.config.codex.workingDirectory,
      model: this.config.codex.model ?? null,
      approvalPolicy: this.config.codex.approvalPolicy,
      sandbox: this.config.codex.sandboxMode,
      config: codexConfigOverrides(this.config.codex)
    };

    const response = capture.threadHint
      ? await session.request("thread/resume", {
          threadId: capture.threadHint,
          ...common
        })
      : await session.request("thread/start", {
          ...common,
          threadSource: "user",
          serviceName: "CodexShot",
          baseInstructions: null,
          developerInstructions: null,
          personality: null,
          ephemeral: null,
          sessionStartSource: null
        });

    const thread = response.thread;
    if (!thread?.id) {
      throw new Error("Codex app-server did not return a thread id.");
    }

    logInfo(this.logger, "codex.app_server.thread_opened", {
      captureId: capture.captureId,
      threadId: thread.id,
      mode: capture.threadHint ? "resume" : "start",
      status: thread.status?.type ?? null
    });

    return thread;
  }
}

export function createDryRunClient() {
  return {
    async deliver(capture) {
      return {
        status: "dry_run",
        threadId: capture.threadHint || "dry-run-thread",
        deliveryLane: "dry-run",
        finalResponse: "Dry run: capture validated and stored; Codex was not called.",
        usage: null
      };
    }
  };
}

export function buildTurnInput(capture, stored) {
  return [
    {
      type: "text",
      text: buildCodexPrompt(capture, stored),
      text_elements: []
    },
    {
      type: "localImage",
      path: stored.imagePath,
      detail: "high"
    }
  ];
}

export function sandboxModeToPolicy(mode) {
  switch (mode) {
    case "danger-full-access":
      return { type: "dangerFullAccess" };
    case "workspace-write":
      return {
        type: "workspaceWrite",
        writableRoots: [],
        networkAccess: false,
        excludeTmpdirEnvVar: false,
        excludeSlashTmp: false
      };
    case "read-only":
    default:
      return { type: "readOnly", networkAccess: false };
  }
}

function codexConfigOverrides(codexConfig) {
  const overrides = {};
  if (codexConfig.webSearchMode) {
    overrides.web_search = codexConfig.webSearchMode;
  }
  if (codexConfig.skipGitRepoCheck) {
    overrides.skip_git_repo_check = true;
  }
  return Object.keys(overrides).length > 0 ? overrides : null;
}

function findActiveTurnId(thread) {
  if (thread.status?.type !== "active") {
    return null;
  }

  const turns = Array.isArray(thread.turns) ? thread.turns : [];
  const activeTurn = [...turns].reverse().find((turn) => turn.status === "inProgress");
  return activeTurn?.id ?? null;
}

class AppServerSession {
  constructor({ binaryPath, processFactory, requestTimeoutMs, logger }) {
    this.binaryPath = binaryPath;
    this.processFactory = processFactory;
    this.requestTimeoutMs = requestTimeoutMs;
    this.logger = logger;
    this.process = null;
    this.nextRequestId = 1;
    this.pending = new Map();
    this.events = new EventEmitter();
    this.stdoutBuffer = "";
    this.stderrBuffer = "";
    this.closed = false;
  }

  async start() {
    this.process = this.processFactory(this.binaryPath, [
      "app-server",
      "--listen",
      "stdio://"
    ]);
    this.process.stdout.setEncoding("utf8");
    this.process.stderr.setEncoding("utf8");
    this.process.stdout.on("data", (chunk) => this.handleStdout(chunk));
    this.process.stderr.on("data", (chunk) => this.handleStderr(chunk));
    this.process.once("exit", (code, signal) => this.handleExit(code, signal));
    this.process.once("error", (error) => this.handleProcessError(error));

    await this.request("initialize", {
      clientInfo: {
        name: "codexshot-relay",
        title: "CodexShot Relay",
        version: "0.1.0"
      },
      capabilities: {
        experimentalApi: true,
        requestAttestation: false,
        optOutNotificationMethods: []
      }
    });
    this.notify("initialized", {});
  }

  request(method, params) {
    const id = this.nextRequestId;
    this.nextRequestId += 1;

    this.send({ method, id, params });
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Codex app-server request timed out: ${method}`));
      }, this.requestTimeoutMs);
      this.pending.set(id, { method, resolve, reject, timeout });
    });
  }

  notify(method, params = {}) {
    this.send({ method, params });
  }

  waitForTurnCompletion(threadId, turnId, timeoutMs) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        cleanup();
        reject(new Error(`Codex app-server turn timed out: ${turnId}`));
      }, timeoutMs);
      const onNotification = (notification) => {
        this.logNotification(notification, threadId, turnId);
        if (notification.method !== "turn/completed") {
          return;
        }
        const params = notification.params ?? {};
        if (params.threadId !== threadId || params.turn?.id !== turnId) {
          return;
        }
        cleanup();
        if (params.turn?.status && params.turn.status !== "completed") {
          const message = params.turn.error?.message
            ? `: ${params.turn.error.message}`
            : "";
          reject(
            new Error(
              `Codex app-server turn ${turnId} finished with status ${params.turn.status}${message}`
            )
          );
          return;
        }
        resolve(params.turn);
      };
      const onExit = (error) => {
        cleanup();
        reject(error);
      };
      const cleanup = () => {
        clearTimeout(timeout);
        this.events.off("notification", onNotification);
        this.events.off("exit", onExit);
      };
      this.events.on("notification", onNotification);
      this.events.once("exit", onExit);
    });
  }

  close() {
    this.closed = true;
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Codex app-server session closed."));
      this.pending.delete(id);
    }
    if (!this.process || this.process.killed) {
      return;
    }
    this.process.stdin.end();
    setTimeout(() => {
      if (this.process && !this.process.killed) {
        this.process.kill("SIGTERM");
      }
    }, 1000).unref();
  }

  send(message) {
    if (!this.process?.stdin.writable) {
      throw new Error("Codex app-server stdin is not writable.");
    }
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  handleStdout(chunk) {
    this.stdoutBuffer += chunk;
    for (;;) {
      const newline = this.stdoutBuffer.indexOf("\n");
      if (newline < 0) {
        return;
      }
      const line = this.stdoutBuffer.slice(0, newline);
      this.stdoutBuffer = this.stdoutBuffer.slice(newline + 1);
      if (line.trim().length === 0) {
        continue;
      }
      this.handleMessageLine(line);
    }
  }

  handleMessageLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch (error) {
      logError(this.logger, "codex.app_server.invalid_json", {
        message: error.message,
        line
      });
      return;
    }

    if (message.id !== undefined && this.pending.has(message.id)) {
      const pending = this.pending.get(message.id);
      this.pending.delete(message.id);
      clearTimeout(pending.timeout);
      if (message.error) {
        pending.reject(
          new Error(
            `Codex app-server ${pending.method} failed: ${message.error.message}`
          )
        );
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (message.method) {
      this.events.emit("notification", message);
    }
  }

  logNotification(notification, threadId, turnId) {
    const method = notification.method;
    const params = notification.params ?? {};
    const notificationThreadId = params.threadId ?? params.thread?.id ?? null;
    const notificationTurnId = params.turn?.id ?? params.turnId ?? null;

    if (notificationThreadId && notificationThreadId !== threadId) {
      return;
    }
    if (notificationTurnId && notificationTurnId !== turnId) {
      return;
    }

    if (
      method === "turn/started" ||
      method === "turn/completed" ||
      method === "turn/failed" ||
      method === "item/started" ||
      method === "item/completed" ||
      method === "item/failed" ||
      method === "error" ||
      method === "warning" ||
      method === "configWarning"
    ) {
      logInfo(this.logger, "codex.app_server.notification", {
        method,
        threadId: notificationThreadId,
        turnId: notificationTurnId,
        itemId: params.item?.id ?? params.itemId ?? null,
        status: params.turn?.status ?? params.item?.status ?? null,
        message:
          params.error?.message ??
          params.turn?.error?.message ??
          params.message ??
          null
      });
    }
  }

  handleStderr(chunk) {
    this.stderrBuffer = `${this.stderrBuffer}${chunk}`.slice(-8192);
    for (const line of chunk.split(/\r?\n/)) {
      if (line.trim()) {
        logInfo(this.logger, "codex.app_server.stderr", { line });
      }
    }
  }

  handleExit(code, signal) {
    if (this.closed) {
      return;
    }
    const error = new Error(
      `Codex app-server exited before delivery completed: ${code ?? signal}`
    );
    this.events.emit("exit", error);
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }

  handleProcessError(error) {
    this.events.emit("exit", error);
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }
}

function defaultProcessFactory(binaryPath, args) {
  return spawn(binaryPath, args, {
    stdio: ["pipe", "pipe", "pipe"]
  });
}
