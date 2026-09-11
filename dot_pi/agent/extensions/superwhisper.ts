// Single-file Superwhisper extension for current Pi.
// Derived from https://github.com/superultrainc/pi-superwhisper (MIT).
// Behavior changes:
// - Superwhisper is OFF by default for every Pi session/runtime.
// - Assistant text is inlined as inbox `message` instead of a sidecar messageFile.

import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  watch,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";

import type {
  AgentEndEvent,
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const execFileAsync = promisify(execFile);

const LOG_PREFIX = "[superwhisper]";
const MESSAGE_DIR = "/tmp/superwhisper-agent";
const INBOX_DIR = join(
  homedir(),
  "Library/Application Support/superwhisper/agent/inbox",
);
const POLL_INTERVAL_MS = 1_000;
const POLL_TIMEOUT_MS = 30 * 60 * 1_000;

const STATUS_COMPLETED = "completed" as const;
const AGENT_PI = "pi" as const;

type AgentMessage = AgentEndEvent["messages"][number];
type AssistantMessage = Extract<AgentMessage, { role: "assistant" }>;

type WaitResult =
  | { kind: "response"; text: string }
  | { kind: "empty" }
  | { kind: "cancelled" }
  | { kind: "timeout" };

interface WaitOptions {
  timeoutMs?: number;
  intervalMs?: number;
  signal?: AbortSignal;
}

type InboxPayload =
  | {
      kind: "dismiss";
      sessionId: string;
    }
  | {
      kind: "update";
      sessionId: string;
      requestId: string;
      agent: typeof AGENT_PI;
      status: typeof STATUS_COMPLETED;
      summary: string;
      message: string;
      responseFile: string;
      cwd: string;
      project: string;
      branch?: string;
      title?: string;
      hookPid: number;
    };

interface NotificationParams {
  sessionId: string;
  summary: string;
  messageContent: string;
  cwd: string;
  title?: string;
}

interface PendingNotification {
  controller: AbortController;
  sessionId: string;
  requestId: string;
}

function getLastAssistant(
  messages: AgentEndEvent["messages"],
): AssistantMessage | undefined {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message.role === "assistant") {
      return message as AssistantMessage;
    }
  }

  return undefined;
}

function extractAssistantText(message: AssistantMessage): string {
  if (!Array.isArray(message.content)) {
    return "";
  }

  return message.content
    .filter(
      (item): item is { type: "text"; text: string } =>
        typeof item === "object" &&
        item !== null &&
        "type" in item &&
        item.type === "text" &&
        "text" in item &&
        typeof item.text === "string",
    )
    .map((item) => item.text)
    .join("\n")
    .trim();
}

function extractSummary(text: string): string {
  const maxLength = 200;
  if (text.length <= maxLength) {
    return text;
  }

  const sentenceEnd = text.slice(0, maxLength).lastIndexOf(". ");
  if (sentenceEnd > 100) {
    return text.slice(0, sentenceEnd + 1);
  }

  const wordEnd = text.slice(0, maxLength).lastIndexOf(" ");
  if (wordEnd > 150) {
    return `${text.slice(0, wordEnd)}...`;
  }

  return `${text.slice(0, maxLength)}...`;
}

function waitForResponse(
  path: string,
  options: WaitOptions = {},
): Promise<WaitResult> {
  const timeoutMs = options.timeoutMs ?? POLL_TIMEOUT_MS;
  const intervalMs = options.intervalMs ?? POLL_INTERVAL_MS;
  const { signal } = options;
  const dir = dirname(path);
  const file = basename(path);

  const tryRead = (): WaitResult | null => {
    try {
      if (!existsSync(path)) {
        return null;
      }

      const text = readFileSync(path, "utf8");
      if (text.trim().length === 0) {
        return { kind: "empty" };
      }

      return { kind: "response", text };
    } catch {
      return null;
    }
  };

  return new Promise<WaitResult>((resolve) => {
    if (signal?.aborted) {
      resolve({ kind: "cancelled" });
      return;
    }

    let settled = false;
    let watcher: ReturnType<typeof watch> | undefined;
    let intervalId: ReturnType<typeof setInterval> | undefined;
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    let abortHandler: (() => void) | undefined;

    const finish = (result: WaitResult): void => {
      if (settled) {
        return;
      }

      settled = true;

      try {
        watcher?.close();
      } catch {
        // Best effort.
      }

      if (intervalId) {
        clearInterval(intervalId);
      }
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
      if (abortHandler && signal) {
        signal.removeEventListener("abort", abortHandler);
      }

      resolve(result);
    };

    const check = (): void => {
      if (settled) {
        return;
      }

      const result = tryRead();
      if (result) {
        finish(result);
      }
    };

    const immediate = tryRead();
    if (immediate) {
      finish(immediate);
      return;
    }

    try {
      watcher = watch(dir, { persistent: false }, (_eventType, filename) => {
        if (filename === file) {
          check();
        }
      });
    } catch {
      // Periodic polling below is the fallback.
    }

    intervalId = setInterval(check, intervalMs);
    timeoutId = setTimeout(() => finish({ kind: "timeout" }), timeoutMs);

    if (signal) {
      abortHandler = () => finish({ kind: "cancelled" });
      signal.addEventListener("abort", abortHandler, { once: true });
    }
  });
}

function removeFile(path: string): void {
  try {
    if (existsSync(path)) {
      unlinkSync(path);
    }
  } catch {
    // Best effort.
  }
}

function writeInboxPayload(payload: InboxPayload): boolean {
  try {
    mkdirSync(INBOX_DIR, { recursive: true });
  } catch {
    return false;
  }

  const id = randomUUID();
  const temporaryPath = join(INBOX_DIR, `${id}.json.tmp`);
  const finalPath = join(INBOX_DIR, `${id}.json`);

  try {
    writeFileSync(temporaryPath, JSON.stringify(payload));
    renameSync(temporaryPath, finalPath);
    return true;
  } catch {
    removeFile(temporaryPath);
    return false;
  }
}

async function isSuperwhisperRunning(): Promise<boolean> {
  try {
    await execFileAsync("pgrep", ["-x", "superwhisper"]);
    return true;
  } catch {
    return false;
  }
}

async function fireAgentWake(scheme: string): Promise<void> {
  try {
    await execFileAsync("open", [`${scheme}://agent-wake`]);
  } catch {
    // Wake is best effort.
  }
}

async function deliverAgentPayload(
  payload: InboxPayload,
  scheme: string,
): Promise<boolean> {
  const wrote = writeInboxPayload(payload);
  const running = await isSuperwhisperRunning();

  if (!running) {
    await fireAgentWake(scheme);
  }

  return wrote;
}

async function detectScheme(): Promise<string> {
  const configuredScheme = process.env.SUPERWHISPER_SCHEME;
  if (configuredScheme) {
    return configuredScheme;
  }

  try {
    await execFileAsync("pgrep", ["-f", "DerivedData.*superwhisper.app"]);
    return "superwhisper-debug";
  } catch {
    return "superwhisper";
  }
}

async function getGitBranch(cwd: string): Promise<string | undefined> {
  try {
    const { stdout } = await execFileAsync("git", [
      "-C",
      cwd,
      "rev-parse",
      "--abbrev-ref",
      "HEAD",
    ]);
    const branch = stdout.trim();
    return branch || undefined;
  } catch {
    return undefined;
  }
}

export default async function superwhisperExtension(
  pi: ExtensionAPI,
): Promise<void> {
  const scheme = await detectScheme();
  mkdirSync(MESSAGE_DIR, { recursive: true });

  const debug = process.env.SUPERWHISPER_DEBUG === "1";
  const logFile = `${MESSAGE_DIR}/debug.log`;

  const log = (
    level: "debug" | "info" | "warn" | "error",
    message: string,
  ): void => {
    if (!debug) {
      return;
    }

    try {
      appendFileSync(
        logFile,
        `[${new Date().toISOString()}] [${level}] ${LOG_PREFIX} ${message}\n`,
      );
    } catch {
      // Logging must never break the extension.
    }
  };

  const deriveSessionId = (ctx: ExtensionContext): string => {
    const sessionFile = ctx.sessionManager.getSessionFile();
    if (sessionFile) {
      return basename(sessionFile).replace(/[^a-zA-Z0-9_.-]/g, "_");
    }

    return `pi-${process.pid}`;
  };

  // This extension runtime serves one active Pi session at a time. OFF is the
  // zero state and every session_start explicitly restores it.
  let enabled = false;
  let pending: PendingNotification | undefined;

  const sendDismiss = (sessionId: string, source: string): void => {
    log("debug", `Sending dismiss (${source}) for session=${sessionId}`);
    void deliverAgentPayload({ kind: "dismiss", sessionId }, scheme).catch(
      (error: unknown) => {
        log(
          "error",
          `Failed to send dismiss for session=${sessionId}: ${String(error)}`,
        );
      },
    );
  };

  const cancelPending = (source: string, dismiss = true): boolean => {
    const current = pending;
    if (!current) {
      return false;
    }

    pending = undefined;
    current.controller.abort();
    log(
      "debug",
      `Notification cancelled request=${current.requestId} (${source})`,
    );

    if (dismiss) {
      sendDismiss(current.sessionId, source);
    }

    return true;
  };

  const setEnabled = (next: boolean, source: string): void => {
    enabled = next;

    if (!next) {
      cancelPending(source);
    }

    log("info", `Superwhisper ${next ? "enabled" : "disabled"} (${source})`);
  };

  const sendNotification = async (
    params: NotificationParams,
  ): Promise<WaitResult> => {
    const { sessionId, summary, messageContent, cwd, title } = params;

    cancelPending("new-notification");

    const requestId = randomUUID();
    const responseFile = join(MESSAGE_DIR, `${requestId}.response`);
    const controller = new AbortController();

    pending = { controller, sessionId, requestId };

    try {
      const branch = await getGitBranch(cwd);
      if (controller.signal.aborted) {
        return { kind: "cancelled" };
      }

      const wrote = await deliverAgentPayload(
        {
          kind: "update",
          agent: AGENT_PI,
          status: STATUS_COMPLETED,
          sessionId,
          requestId,
          summary,
          message: messageContent,
          responseFile,
          cwd,
          project: basename(cwd) || "pi",
          branch,
          title,
          hookPid: process.pid,
        },
        scheme,
      );

      if (!wrote) {
        throw new Error("Failed to write Superwhisper inbox payload");
      }

      if (controller.signal.aborted) {
        return { kind: "cancelled" };
      }

      log(
        "info",
        `Notification sent request=${requestId} session=${sessionId}`,
      );

      return await waitForResponse(responseFile, {
        signal: controller.signal,
      });
    } finally {
      if (pending?.controller === controller) {
        pending = undefined;
      }

      removeFile(responseFile);
    }
  };

  pi.on("session_start", () => {
    setEnabled(false, "session_start");
  });

  pi.on("agent_start", () => {
    // A manually started turn makes any prior voice prompt stale.
    cancelPending("agent_start");
  });

  pi.on("agent_end", async (event, ctx) => {
    const sessionId = deriveSessionId(ctx);

    if (!enabled) {
      log("debug", `Skipping agent_end for session=${sessionId} (disabled)`);
      return;
    }

    const assistant = getLastAssistant(event.messages);
    if (!assistant) {
      log("info", `Skipping agent_end without assistant for session=${sessionId}`);
      return;
    }

    if (assistant.stopReason !== "stop") {
      log(
        "info",
        `Skipping non-end-turn agent_end for session=${sessionId} ` +
          `(stopReason=${assistant.stopReason})`,
      );
      return;
    }

    const fullMessage = extractAssistantText(assistant);
    if (!fullMessage) {
      log("info", `Skipping empty completion for session=${sessionId}`);
      return;
    }

    let outcome: WaitResult;
    try {
      outcome = await sendNotification({
        sessionId,
        summary: extractSummary(fullMessage),
        messageContent: fullMessage,
        cwd: ctx.cwd,
        title: ctx.sessionManager.getSessionName(),
      });
    } catch (error: unknown) {
      log(
        "error",
        `Superwhisper notification failed for session=${sessionId}: ${String(error)}`,
      );
      sendDismiss(sessionId, "notification-error");
      return;
    }

    switch (outcome.kind) {
      case "response":
        try {
          pi.sendUserMessage(outcome.text, { deliverAs: "followUp" });
          log("info", `Voice response sent to Pi for session=${sessionId}`);
        } catch (error: unknown) {
          log("error", `Failed to send user message: ${String(error)}`);
        }
        return;

      case "empty":
        log("info", `User dismissed notification for session=${sessionId}`);
        return;

      case "cancelled":
        log("info", `Notification cancelled for session=${sessionId}`);
        return;

      case "timeout":
        log("info", `Poll timed out for session=${sessionId}`);
        sendDismiss(sessionId, "completed-timeout");
        return;
    }
  });

  pi.on("session_shutdown", () => {
    setEnabled(false, "session_shutdown");
  });

  pi.registerTool({
    name: "superwhisper_toggle",
    label: "Superwhisper",
    description:
      "Enable or disable Superwhisper voice notifications for this Pi session. " +
      "Superwhisper starts disabled by default. Use action='enable' when the user " +
      "explicitly asks to enable Superwhisper, voice notifications, or hands-free mode.",
    promptSnippet:
      "Toggle Superwhisper voice notifications for this Pi session. It is disabled by default.",
    promptGuidelines: [
      "Only enable Superwhisper when the user explicitly asks to enable Superwhisper, voice notifications, or hands-free mode.",
      "Use superwhisper_toggle with action='disable' when the user asks to turn it off.",
    ],
    parameters: Type.Object({
      action: Type.Union([Type.Literal("enable"), Type.Literal("disable")]),
    }),
    async execute(_toolCallId, params) {
      const next = params.action === "enable";
      setEnabled(next, "toggle-tool");

      return {
        content: [
          {
            type: "text",
            text:
              `Superwhisper voice notifications are ${next ? "enabled" : "disabled"} ` +
              "for this session.",
          },
        ],
        details: undefined,
        isError: false,
      };
    },
  });

  pi.registerCommand("superwhisper", {
    description:
      "Enable, disable, test, or inspect Superwhisper voice notifications for this session",
    handler: async (args: string, ctx: ExtensionCommandContext) => {
      const action = args.trim().toLowerCase();

      if (action === "off" || action === "disable") {
        setEnabled(false, "slash-command");
        ctx.ui.notify("Superwhisper disabled for this session", "info");
        return;
      }

      if (action === "on" || action === "enable") {
        setEnabled(true, "slash-command");
        ctx.ui.notify("Superwhisper enabled for this session", "info");
        return;
      }

      if (action === "test") {
        const sessionId = deriveSessionId(ctx);

        try {
          const outcome = await sendNotification({
            sessionId,
            summary: "Pi Superwhisper test",
            messageContent: "This is a Pi Superwhisper test notification.",
            cwd: ctx.cwd,
            title: ctx.sessionManager.getSessionName(),
          });

          log("info", `Test notification outcome: ${outcome.kind}`);
          ctx.ui.notify(
            `Superwhisper test finished: ${outcome.kind}`,
            outcome.kind === "timeout" ? "warning" : "info",
          );
        } catch (error: unknown) {
          log("error", `Test notification failed: ${String(error)}`);
          ctx.ui.notify("Superwhisper test failed", "warning");
        }
        return;
      }

      if (action === "" || action === "status") {
        ctx.ui.notify(
          `Superwhisper is ${enabled ? "enabled" : "disabled"} for this session. ` +
            "Usage: /superwhisper [on|off|test|status]",
          "info",
        );
        return;
      }

      ctx.ui.notify("Usage: /superwhisper [on|off|test|status]", "info");
    },
  });
}
