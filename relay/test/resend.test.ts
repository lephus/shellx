import { afterEach, describe, expect, it, vi } from "vitest";
import { RESEND_EMAILS_URL, RESEND_TIMEOUT_MS, ResendClient } from "../src/email/resend.js";
import { signInCodeEmail } from "../src/email/sign-in-code.js";

afterEach(() => vi.restoreAllMocks());

const KEY = "placeholder-not-a-real-key";
const MESSAGE = { to: "ann.lee@example.com", subject: "s", text: "t", html: "<p>h</p>", idempotencyKey: "7f1c0a52-3b0e-4d3a-9a39-0d5b0c7f2a11" };

function fakeFetch(answer: { status: number; body?: string } | Error | "hang") {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {} });
    if (answer === "hang") {
      const signal = init!.signal!;
      return new Promise<Response>((_, reject) => signal.addEventListener("abort", () => reject(signal.reason)));
    }
    if (answer instanceof Error) throw answer;
    return new Response(answer.body ?? "{}", { status: answer.status });
  }) as typeof fetch;
  return { fn, calls };
}

describe("ResendClient", () => {
  it("posts one JSON message to Resend with the key, the idempotency key and a User-Agent, for at most 10 s", async () => {
    const f = fakeFetch({ status: 200, body: '{"id":"49a3999c"}' });
    expect(await new ResendClient({ apiKey: KEY, from: "ShellX <sign-in@shellx.pro>", fetch: f.fn }).send(MESSAGE)).toEqual({ ok: true });
    expect([RESEND_EMAILS_URL, RESEND_TIMEOUT_MS]).toEqual(["https://api.resend.com/emails", 10_000]);
    expect(f.calls).toHaveLength(1);
    const { url, init } = f.calls[0]!;
    const headers = new Headers(init.headers);
    expect([url, init.method, init.redirect]).toEqual(["https://api.resend.com/emails", "POST", "error"]);
    expect([headers.get("authorization"), headers.get("content-type"), headers.get("idempotency-key"), headers.get("user-agent")])
      .toEqual([`Bearer ${KEY}`, "application/json", MESSAGE.idempotencyKey, "shellx-relay"]);
    expect(JSON.parse(String(init.body))).toEqual({ from: "ShellX <sign-in@shellx.pro>", to: ["ann.lee@example.com"], subject: "s", text: "t", html: "<p>h</p>" });
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it.each([400, 401, 403, 422, 429, 500, 503])("answers {ok: false, status} to a %i, without retrying", async (status) => {
    const f = fakeFetch({ status, body: '{"message":"ann.lee@example.com is not allowed"}' });
    expect(await new ResendClient({ apiKey: KEY, from: "sign-in@shellx.pro", fetch: f.fn }).send(MESSAGE)).toEqual({ ok: false, status });
    expect(f.calls).toHaveLength(1);
  });

  it("answers {ok: false, error} when the request fails or outlasts the timeout; never throws and never logs", async () => {
    const lines: string[] = [];
    for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
    const reset = Object.assign(new Error("connect ECONNRESET 203.0.113.9:443"), { code: "ECONNRESET" });
    const down = new ResendClient({ apiKey: KEY, from: "sign-in@shellx.pro", fetch: fakeFetch(reset).fn });
    expect(await down.send(MESSAGE)).toEqual({ ok: false, error: "ECONNRESET" });
    const slow = new ResendClient({ apiKey: KEY, from: "sign-in@shellx.pro", fetch: fakeFetch("hang").fn, timeoutMs: 20 });
    expect(await slow.send(MESSAGE)).toEqual({ ok: false, error: "TimeoutError" });
    expect(lines).toEqual([]);
  });
});

describe("the sign-in code email", () => {
  it("has the fixed subjects and the same three sentences as text and as HTML, in English and Vietnamese", () => {
    const en = signInCodeEmail("048213", "en");
    const vn = signInCodeEmail("048213", "vi");
    expect(en.subject).toBe("Your ShellX sign-in code is 048213");
    expect(vn.subject).toBe("Mã đăng nhập ShellX của bạn là 048213");
    expect(en.text).toBe(
      "Your ShellX sign-in code is 048213\n\nEnter this code in ShellX within 10 minutes.\n\n" +
      "If you did not ask for it, ignore this email: nobody can sign in without the code. ShellX will never ask you for this code by email, phone or chat.\n",
    );
    expect(vn.text).toBe(
      "Mã đăng nhập ShellX của bạn là 048213\n\nNhập mã này vào ShellX trong vòng 10 phút.\n\n" +
      "Nếu bạn không yêu cầu mã, hãy bỏ qua email này: không ai đăng nhập được nếu không có mã. ShellX không bao giờ hỏi bạn mã này qua email, điện thoại hay tin nhắn.\n",
    );
    for (const mail of [en, vn]) {
      for (const sentence of mail.text.split("\n").filter((line) => line !== "").slice(1)) expect(mail.html).toContain(sentence);
      expect(mail.html).toContain(">048213<");
    }
    expect([en.html.includes('lang="en"'), vn.html.includes('lang="vi"')]).toEqual([true, true]);
  });

  it("has nothing to click or load: no link, image, script or remote reference", () => {
    for (const locale of ["en", "vi"] as const) {
      const mail = signInCodeEmail("048213", locale);
      expect(mail.html).not.toMatch(/https?:|www\.|href|<a[\s>]|<img|<script|<link|<style|src=|url\(|@import/i);
      expect(mail.text).not.toMatch(/https?:|www\./i);
    }
  });
});
