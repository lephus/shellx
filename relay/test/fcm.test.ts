import { generateKeyPairSync, createVerify } from "node:crypto";
import { describe, expect, it } from "vitest";
import { loadPush, loopbackUrl } from "../src/push/config.js";
import {
  FCM_SCOPE, FcmClient, parseServiceAccount, ServiceAccountError, TOKEN_RENEW_MARGIN_MS, type PushMessage, type ServiceAccount,
} from "../src/push/fcm.js";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});

const ACCOUNT_JSON = JSON.stringify({
  type: "service_account",
  project_id: "shellxpro",
  private_key_id: "abc",
  private_key: privateKey,
  client_email: "push@shellxpro.iam.gserviceaccount.com",
  token_uri: "https://oauth2.googleapis.com/token",
});
const ACCOUNT: ServiceAccount = parseServiceAccount(ACCOUNT_JSON);

const MESSAGE: PushMessage = { token: "phone-token", title: "Mac · Session 1", body: "✓ make · 45 s", data: { kind: "command" } };

interface Recorded {
  url: string;
  init: RequestInit;
}

/** A fake `fetch`: token requests get `tokenReply`, sends get `sendReply()`. */
function fakeFetch(opts: { sendReply?: () => Response; tokenReply?: () => Response } = {}) {
  const calls: Recorded[] = [];
  let tokens = 0;
  const fn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init: init ?? {} });
    if (url.includes("token")) {
      tokens++;
      return opts.tokenReply?.() ?? Response.json({ access_token: `access-${tokens}`, expires_in: 3600, token_type: "Bearer" });
    }
    return opts.sendReply?.() ?? Response.json({ name: "projects/shellxpro/messages/1" });
  }) as typeof fetch;
  return { fn, calls, sends: () => calls.filter((c) => !c.url.includes("token")), tokenCalls: () => calls.filter((c) => c.url.includes("token")) };
}

function fcmError(status: number, code: string, errorCode?: string): Response {
  return Response.json(
    {
      error: {
        code: status,
        message: "x",
        status: code,
        details: errorCode === undefined ? [] : [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode }],
      },
    },
    { status },
  );
}

describe("parseServiceAccount", () => {
  it("reads project_id, client_email, private_key and token_uri", () => {
    expect(ACCOUNT).toEqual({
      projectId: "shellxpro",
      clientEmail: "push@shellxpro.iam.gserviceaccount.com",
      privateKey,
      tokenUri: "https://oauth2.googleapis.com/token",
    });
  });

  it("refuses anything that is not a usable key", () => {
    const base = JSON.parse(ACCOUNT_JSON) as Record<string, unknown>;
    for (const text of [
      "not json",
      "[]",
      JSON.stringify({ ...base, project_id: undefined }),
      JSON.stringify({ ...base, client_email: "" }),
      JSON.stringify({ ...base, private_key: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n" }),
      JSON.stringify({ ...base, project_id: "../evil" }),
    ]) {
      expect(() => parseServiceAccount(text), text.slice(0, 40)).toThrow(ServiceAccountError);
    }
  });

  it("defaults token_uri to Google's", () => {
    const base = JSON.parse(ACCOUNT_JSON) as Record<string, unknown>;
    delete base.token_uri;
    expect(parseServiceAccount(JSON.stringify(base)).tokenUri).toBe("https://oauth2.googleapis.com/token");
  });
});

describe("FcmClient", () => {
  it("gets an access token with an RS256 JWT assertion signed by the service account", async () => {
    const f = fakeFetch();
    const now = 1_800_000_000_000;
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn, now: () => now });
    expect(await client.send(MESSAGE)).toBe("ok");
    const tokenCall = f.tokenCalls()[0]!;
    expect(tokenCall.url).toBe("https://oauth2.googleapis.com/token");
    expect(tokenCall.init.method).toBe("POST");
    expect(new Headers(tokenCall.init.headers).get("content-type")).toBe("application/x-www-form-urlencoded");
    const form = new URLSearchParams(String(tokenCall.init.body));
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    const [header, claims, signature] = form.get("assertion")!.split(".");
    expect(JSON.parse(Buffer.from(header!, "base64url").toString())).toEqual({ alg: "RS256", typ: "JWT" });
    expect(JSON.parse(Buffer.from(claims!, "base64url").toString())).toEqual({
      iss: "push@shellxpro.iam.gserviceaccount.com",
      scope: FCM_SCOPE,
      aud: "https://oauth2.googleapis.com/token",
      iat: now / 1000,
      exp: now / 1000 + 3600,
    });
    const verifier = createVerify("RSA-SHA256");
    verifier.update(`${header}.${claims}`);
    expect(verifier.verify(publicKey, Buffer.from(signature!, "base64url"))).toBe(true);
  });

  it("sends the HTTP v1 message: notification, data, android high priority, APNs default sound", async () => {
    const f = fakeFetch();
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
    await client.send(MESSAGE);
    const send = f.sends()[0]!;
    expect(send.url).toBe("https://fcm.googleapis.com/v1/projects/shellxpro/messages:send");
    expect(new Headers(send.init.headers).get("authorization")).toBe("Bearer access-1");
    expect(JSON.parse(String(send.init.body))).toEqual({
      message: {
        token: "phone-token",
        notification: { title: "Mac · Session 1", body: "✓ make · 45 s" },
        data: { kind: "command" },
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
      },
    });
  });

  it("caches the access token until a minute before it expires", async () => {
    const f = fakeFetch();
    let now = 1_800_000_000_000;
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn, now: () => now });
    await client.send(MESSAGE);
    now += 3600_000 - TOKEN_RENEW_MARGIN_MS - 1;
    await client.send(MESSAGE);
    expect(f.tokenCalls()).toHaveLength(1);
    now += 1;
    await client.send(MESSAGE);
    expect(f.tokenCalls()).toHaveLength(2);
    expect(new Headers(f.sends()[2]!.init.headers).get("authorization")).toBe("Bearer access-2");
  });

  it("asks for one token when many sends start at once", async () => {
    const f = fakeFetch();
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
    const results = await Promise.all([1, 2, 3, 4].map(() => client.send(MESSAGE)));
    expect(results).toEqual(["ok", "ok", "ok", "ok"]);
    expect(f.tokenCalls()).toHaveLength(1);
  });

  it("maps UNREGISTERED, and INVALID_ARGUMENT about message.token, to invalid_token", async () => {
    const tokenViolation = () =>
      Response.json(
        {
          error: {
            code: 400,
            status: "INVALID_ARGUMENT",
            details: [
              { "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "INVALID_ARGUMENT" },
              { "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.token", description: "Invalid registration token" }] },
            ],
          },
        },
        { status: 400 },
      );
    for (const reply of [() => fcmError(404, "NOT_FOUND", "UNREGISTERED"), tokenViolation]) {
      const client = new FcmClient({ account: ACCOUNT, fetch: fakeFetch({ sendReply: reply }).fn });
      expect(await client.send(MESSAGE)).toBe("invalid_token");
    }
  });

  it("an INVALID_ARGUMENT about the payload is an error, never invalid_token (the token is kept)", async () => {
    const payloadViolation = () =>
      Response.json(
        {
          error: {
            code: 400,
            status: "INVALID_ARGUMENT",
            details: [{ "@type": "type.googleapis.com/google.rpc.BadRequest", fieldViolations: [{ field: "message.data", description: "too big" }] }],
          },
        },
        { status: 400 },
      );
    for (const reply of [
      () => fcmError(400, "INVALID_ARGUMENT", "INVALID_ARGUMENT"),
      () => fcmError(400, "INVALID_ARGUMENT"),
      payloadViolation,
    ]) {
      const client = new FcmClient({ account: ACCOUNT, fetch: fakeFetch({ sendReply: reply }).fn });
      expect(await client.send(MESSAGE)).toBe("error");
    }
  });

  it("reports other failures as error without retrying", async () => {
    for (const reply of [
      () => fcmError(503, "UNAVAILABLE", "UNAVAILABLE"),
      () => fcmError(429, "RESOURCE_EXHAUSTED", "QUOTA_EXCEEDED"),
      () => fcmError(403, "PERMISSION_DENIED", "SENDER_ID_MISMATCH"),
      () => new Response("<html>bad gateway</html>", { status: 502 }),
    ]) {
      const f = fakeFetch({ sendReply: reply });
      const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
      expect(await client.send(MESSAGE)).toBe("error");
      expect(f.sends()).toHaveLength(1);
    }
  });

  it("drops the cached access token after a 401, and fetches a new one next time", async () => {
    let first = true;
    const f = fakeFetch({
      sendReply: () => {
        if (!first) return Response.json({ name: "ok" });
        first = false;
        return fcmError(401, "UNAUTHENTICATED", "THIRD_PARTY_AUTH_ERROR");
      },
    });
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
    expect(await client.send(MESSAGE)).toBe("error");
    expect(await client.send(MESSAGE)).toBe("ok");
    expect(f.tokenCalls()).toHaveLength(2);
  });

  it("a refused token request is an error, and is tried again on the next send", async () => {
    let refuse = true;
    const f = fakeFetch({ tokenReply: () => (refuse ? new Response("no", { status: 400 }) : Response.json({ access_token: "a", expires_in: 3600 })) });
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn });
    expect(await client.send(MESSAGE)).toBe("error");
    expect(f.sends()).toHaveLength(0);
    refuse = false;
    expect(await client.send(MESSAGE)).toBe("ok");
  });

  it("a network failure is an error", async () => {
    const fn = (async () => {
      throw Object.assign(new TypeError("fetch failed"), { code: "ECONNREFUSED" });
    }) as typeof fetch;
    expect(await new FcmClient({ account: ACCOUNT, fetch: fn }).send(MESSAGE)).toBe("error");
  });

  it("uses the endpoint and token endpoint overrides", async () => {
    const f = fakeFetch();
    const client = new FcmClient({ account: ACCOUNT, fetch: f.fn, endpoint: "http://127.0.0.1:9999/", tokenEndpoint: "http://127.0.0.1:9999/token" });
    await client.send(MESSAGE);
    expect(f.calls.map((c) => c.url)).toEqual([
      "http://127.0.0.1:9999/token",
      "http://127.0.0.1:9999/v1/projects/shellxpro/messages:send",
    ]);
  });
});

describe("loadPush (FCM_SERVICE_ACCOUNT)", () => {
  it("is off without FCM_SERVICE_ACCOUNT", () => {
    expect(loadPush({})).toEqual({ gateway: null, reason: "not_configured" });
    expect(loadPush({ FCM_SERVICE_ACCOUNT: "  " })).toEqual({ gateway: null, reason: "not_configured" });
  });

  it("is off when the file cannot be read or is not a service account key", () => {
    expect(loadPush({ FCM_SERVICE_ACCOUNT: "/nope/fcm.json" })).toEqual({ gateway: null, reason: "unreadable" });
    expect(loadPush({ FCM_SERVICE_ACCOUNT: "/x" }, { readFile: () => "{}" })).toEqual({ gateway: null, reason: "invalid" });
  });

  it("builds an FcmClient from a valid key, honouring loopback overrides only", async () => {
    const f = fakeFetch();
    const setup = loadPush(
      { FCM_SERVICE_ACCOUNT: "/secrets/fcm.json", FCM_ENDPOINT: "http://127.0.0.1:8788", FCM_TOKEN_ENDPOINT: "http://localhost:8788/token" },
      { readFile: () => ACCOUNT_JSON, fetch: f.fn },
    );
    expect(setup.gateway).toBeInstanceOf(FcmClient);
    await setup.gateway!.send(MESSAGE);
    expect(f.calls.map((c) => c.url)).toEqual(["http://localhost:8788/token", "http://127.0.0.1:8788/v1/projects/shellxpro/messages:send"]);
  });

  it("ignores overrides that are not loopback URLs", () => {
    expect(loopbackUrl("https://evil.example.com")).toBeUndefined();
    expect(loopbackUrl("http://127.0.0.1.evil.com/")).toBeUndefined();
    expect(loopbackUrl("file:///etc/passwd")).toBeUndefined();
    expect(loopbackUrl("nonsense")).toBeUndefined();
    expect(loopbackUrl(undefined)).toBeUndefined();
    expect(loopbackUrl("http://[::1]:8788/")).toBe("http://[::1]:8788");
    expect(loopbackUrl("http://127.0.0.1:8788/token")).toBe("http://127.0.0.1:8788/token");
  });
});
