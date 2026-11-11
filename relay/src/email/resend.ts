import { errorKind } from "../log.js";

export const RESEND_EMAILS_URL = "https://api.resend.com/emails";
export const RESEND_TIMEOUT_MS = 10_000;
/** Resend answers 403 to a request without a User-Agent. */
export const RESEND_USER_AGENT = "shellx-relay";

export interface EmailMessage {
  /** One recipient, already normalized. */
  to: string;
  subject: string;
  text: string;
  html: string;
  /** Sent as `Idempotency-Key`: the same key is never delivered twice. */
  idempotencyKey: string;
}

/** `status`: the gateway answered, but not 2xx. `error`: a loggable kind (`errorKind`), never a message. */
export type EmailSendResult = { ok: true } | { ok: false; status?: number; error?: string };

/** Sends one mail. Never throws and never logs: the caller logs `status` or `error`, and nothing else. */
export interface EmailGateway {
  send(message: EmailMessage): Promise<EmailSendResult>;
}

/**
 * Resend's HTTP API (spec 2026-11-10 §6): one POST per mail, no retry. A redirect is an error (the key
 * must not follow one), and the request is given up after `timeoutMs`.
 */
export class ResendClient implements EmailGateway {
  private readonly fetchFn: typeof fetch;
  private readonly timeoutMs: number;

  constructor(private readonly options: { apiKey: string; from: string; fetch?: typeof fetch; timeoutMs?: number }) {
    this.fetchFn = options.fetch ?? fetch;
    this.timeoutMs = options.timeoutMs ?? RESEND_TIMEOUT_MS;
  }

  async send(message: EmailMessage): Promise<EmailSendResult> {
    let res: Response;
    try {
      res = await this.fetchFn(RESEND_EMAILS_URL, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.options.apiKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": message.idempotencyKey,
          "User-Agent": RESEND_USER_AGENT,
        },
        body: JSON.stringify({ from: this.options.from, to: [message.to], subject: message.subject, text: message.text, html: message.html }),
        redirect: "error",
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (err) {
      return { ok: false, error: errorKind(err) };
    }
    // The answer's body may quote the recipient: it is dropped unread. Dropping it never changes the result.
    try {
      void res.body?.cancel().catch(() => undefined);
    } catch {
      // nothing to release
    }
    return res.status >= 200 && res.status <= 299 ? { ok: true } : { ok: false, status: res.status };
  }
}
