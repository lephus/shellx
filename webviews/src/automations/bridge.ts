import type { AutomationsEvent, AutomationsMethod, AutomationsReply } from "./types";

// Page side of the `shellxAutomations` bridge (Swift host: Task 8).
//
// Requests are `{ method, params }`, posted to a WKScriptMessageHandlerWithReply
// whose promise resolves to `{ ok: true, result }` or
// `{ ok: false, error: { code, message } }`. The host pushes events by calling
// `window.shellxAutomations.receive(event)`.

export type AutomationsMessageHandler = { postMessage(message: unknown): Promise<unknown> };

export type AutomationsHost = {
  webkit?: { messageHandlers?: { shellxAutomations?: AutomationsMessageHandler } };
  shellxAutomations?: { receive(event: AutomationsEvent): void };
};

export type AutomationsBridge = {
  request<T>(method: AutomationsMethod, params?: object): Promise<AutomationsReply<T>>;
  onEvent(cb: (e: AutomationsEvent) => void): () => void;
};

function isReply(value: unknown): value is AutomationsReply<unknown> {
  if (typeof value !== "object" || value === null) return false;
  const reply = value as { ok?: unknown; error?: unknown };
  if (typeof reply.ok !== "boolean") return false;
  if (reply.ok) return true;
  const error = reply.error as { code?: unknown; message?: unknown } | null | undefined;
  return typeof error === "object" && error !== null && typeof error.code === "string";
}

const EVENT_TYPES = ["automations.changed", "creator.event", "focus", "appearance"];

function isEvent(value: unknown): value is AutomationsEvent {
  if (typeof value !== "object" || value === null) return false;
  const type = (value as { type?: unknown }).type;
  return typeof type === "string" && EVENT_TYPES.includes(type);
}

export function createAutomationsBridge(host: AutomationsHost = window): AutomationsBridge {
  const listeners = new Set<(e: AutomationsEvent) => void>();
  const failure = (message: string): AutomationsReply<never> => ({
    ok: false,
    error: { code: "failed", message },
  });

  host.shellxAutomations = {
    receive(event) {
      if (!isEvent(event)) return;
      for (const listener of listeners) listener(event);
    },
  };

  return {
    async request<T>(method: AutomationsMethod, params: object = {}): Promise<AutomationsReply<T>> {
      const handler = host.webkit?.messageHandlers?.shellxAutomations;
      if (!handler) return failure("The shellxAutomations handler is not available.");
      let reply: unknown;
      try {
        reply = await handler.postMessage({ method, params });
      } catch (error) {
        return failure(error instanceof Error ? error.message : String(error));
      }
      if (!isReply(reply)) return failure("Malformed reply.");
      return reply as AutomationsReply<T>;
    },
    onEvent(cb) {
      listeners.add(cb);
      return () => {
        listeners.delete(cb);
      };
    },
  };
}
