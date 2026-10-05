import { readFileSync } from "node:fs";
import { FcmClient, parseServiceAccount, type PushGateway } from "./fcm.js";

/** Why push is off: no `FCM_SERVICE_ACCOUNT`, the file cannot be read, or it is not a usable key. */
export type PushDisabledReason = "not_configured" | "unreadable" | "invalid";

export type PushSetup =
  | { gateway: PushGateway; projectId: string }
  | { gateway: null; reason: PushDisabledReason };

export interface LoadPushOptions {
  readFile?: (path: string) => string;
  fetch?: typeof fetch;
}

/**
 * Only loopback http(s) URLs are honoured for the test overrides `FCM_ENDPOINT` and
 * `FCM_TOKEN_ENDPOINT`, so a stray value in production can never send the access token (or the
 * notifications) anywhere but Google.
 */
export function loopbackUrl(value: string | undefined): string | undefined {
  if (value === undefined || value.trim() === "") return undefined;
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return undefined;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return undefined;
  if (!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) return undefined;
  return url.toString().replace(/\/+$/, "");
}

/**
 * Push configuration (push spec §5): `FCM_SERVICE_ACCOUNT` is the path of the service account JSON
 * key (mounted read-only into the container). Missing, unreadable or invalid → push is off and the
 * relay keeps running; `POST /v1/notifications` then answers 503 `push_unavailable`.
 */
export function loadPush(env: Readonly<Record<string, string | undefined>>, options: LoadPushOptions = {}): PushSetup {
  const path = env.FCM_SERVICE_ACCOUNT?.trim();
  if (path === undefined || path === "") return { gateway: null, reason: "not_configured" };
  let text: string;
  try {
    text = (options.readFile ?? ((p) => readFileSync(p, "utf8")))(path);
  } catch {
    return { gateway: null, reason: "unreadable" };
  }
  try {
    const account = parseServiceAccount(text);
    const gateway = new FcmClient({
      account,
      fetch: options.fetch,
      endpoint: loopbackUrl(env.FCM_ENDPOINT),
      tokenEndpoint: loopbackUrl(env.FCM_TOKEN_ENDPOINT),
    });
    return { gateway, projectId: account.projectId };
  } catch {
    return { gateway: null, reason: "invalid" };
  }
}
