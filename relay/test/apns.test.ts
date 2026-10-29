import { createPublicKey, generateKeyPairSync, verify } from "node:crypto";
import { createServer, type Http2Server } from "node:http2";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import {
  APNS_JWT_TTL_MS, ApnsClient, http2Transport, loadApns, type ApnsMessage, type ApnsRequest, type ApnsTransport,
} from "../src/push/apns.js";

const { privateKey } = generateKeyPairSync("ec", {
  namedCurve: "prime256v1",
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});
const KEY = { keyId: "KEY1234567", teamId: "TEAM123456", privateKeyPem: privateKey };
const TOKEN = "a".repeat(64);

const ALERT: ApnsMessage = {
  token: TOKEN, topic: "com.shellx.prod", environment: "production", pushType: "alert", priority: 10,
  collapseId: "req-1", expiresAtSec: 1_800_000_000, payload: { aps: { alert: { "loc-key": "push.needsYou" } } },
};

/** A transport that records each request and answers from `answers` in turn (200 once they run out). */
function recording(answers: { status: number; body?: string }[] = []): { transport: ApnsTransport; requests: ApnsRequest[] } {
  const requests: ApnsRequest[] = [];
  const transport: ApnsTransport = async (request) => {
    requests.push(request);
    const answer = answers.shift() ?? { status: 200 };
    return { status: answer.status, body: answer.body ?? "" };
  };
  return { transport, requests };
}

function jwtOf(request: ApnsRequest): { header: Record<string, unknown>; claims: Record<string, unknown>; valid: boolean } {
  const auth = request.headers.authorization;
  expect(auth).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  const [header, claims, signature] = auth!.slice("bearer ".length).split(".") as [string, string, string];
  const valid = verify(
    "sha256", Buffer.from(`${header}.${claims}`), { key: createPublicKey(privateKey), dsaEncoding: "ieee-p1363" },
    Buffer.from(signature, "base64url"),
  );
  return {
    header: JSON.parse(Buffer.from(header, "base64url").toString()),
    claims: JSON.parse(Buffer.from(claims, "base64url").toString()),
    valid,
  };
}

describe("ApnsClient", () => {
  it("posts the payload to the token's host with the APNs headers and a signed ES256 token", async () => {
    const { transport, requests } = recording();
    const client = new ApnsClient({ key: KEY, transport, now: () => 1_700_000_000_000 });

    expect(await client.send(ALERT)).toBe("ok");

    const [request] = requests;
    expect(request!.origin).toBe("https://api.push.apple.com");
    expect(request!.path).toBe(`/3/device/${TOKEN}`);
    expect(request!.headers).toMatchObject({
      "apns-topic": "com.shellx.prod", "apns-push-type": "alert", "apns-priority": "10",
      "apns-collapse-id": "req-1", "apns-expiration": "1800000000",
    });
    expect(JSON.parse(request!.body)).toEqual(ALERT.payload);
    const jwt = jwtOf(request!);
    expect(jwt.valid).toBe(true);
    expect(jwt.header).toEqual({ alg: "ES256", kid: "KEY1234567" });
    expect(jwt.claims).toEqual({ iss: "TEAM123456", iat: 1_700_000_000 });
  });

  it("sends a sandbox token to the sandbox host, without a collapse id when there is none", async () => {
    const { transport, requests } = recording();
    const client = new ApnsClient({ key: KEY, transport });

    await client.send({ ...ALERT, environment: "sandbox", pushType: "background", priority: 5, collapseId: undefined });

    expect(requests[0]!.origin).toBe("https://api.sandbox.push.apple.com");
    expect(requests[0]!.headers["apns-push-type"]).toBe("background");
    expect(requests[0]!.headers["apns-priority"]).toBe("5");
    expect(requests[0]!.headers).not.toHaveProperty("apns-collapse-id");
  });

  it("reuses its signed token until it is 50 minutes old", async () => {
    let now = 1_700_000_000_000;
    const { transport, requests } = recording();
    const client = new ApnsClient({ key: KEY, transport, now: () => now });

    await client.send(ALERT);
    now += APNS_JWT_TTL_MS - 1;
    await client.send(ALERT);
    now += 1;
    await client.send(ALERT);

    const [first, second, third] = requests.map((r) => r.headers.authorization);
    expect(second).toBe(first);
    expect(third).not.toBe(first);
  });

  it.each([
    [410, "Unregistered", "invalid_token"],
    [400, "BadDeviceToken", "invalid_token"],
    [400, "DeviceTokenNotForTopic", "invalid_token"],
    [400, "PayloadTooLarge", "error"],
    [429, "TooManyRequests", "error"],
    [500, "InternalServerError", "error"],
  ] as const)("maps %i %s to %s", async (status, reason, result) => {
    const { transport } = recording([{ status, body: JSON.stringify({ reason }) }]);
    expect(await new ApnsClient({ key: KEY, transport }).send(ALERT)).toBe(result);
  });

  it("retries once with a fresh provider token when APNs refuses the cached one", async () => {
    const { transport, requests } = recording([{ status: 403, body: JSON.stringify({ reason: "ExpiredProviderToken" }) }]);
    let now = 1_700_000_000_000;
    // Each reading is a second later, so a token signed again differs from the refused one.
    const client = new ApnsClient({ key: KEY, transport, now: () => (now += 1_000) });

    expect(await client.send(ALERT)).toBe("ok");

    expect(requests).toHaveLength(2);
    expect(requests[1]!.headers.authorization).not.toBe(requests[0]!.headers.authorization);
  });

  it("retries a refused provider token only once", async () => {
    const refused = { status: 403, body: JSON.stringify({ reason: "InvalidProviderToken" }) };
    const { transport, requests } = recording([refused, refused, refused]);
    const client = new ApnsClient({ key: KEY, transport });
    expect(await client.send(ALERT)).toBe("error");
    expect(requests).toHaveLength(2);
  });

  it("answers error when the connection fails", async () => {
    const client = new ApnsClient({ key: KEY, transport: async () => { throw new Error("ECONNRESET"); } });
    expect(await client.send(ALERT)).toBe("error");
  });
});

describe("http2Transport", () => {
  let server: Http2Server | undefined;
  afterEach(() => new Promise<void>((resolve) => (server ? server.close(() => resolve()) : resolve())));

  it("sends the request over HTTP/2 and returns the status and body", async () => {
    const seen: { path?: string; topic?: string; body: string } = { body: "" };
    server = createServer((req, res) => {
      seen.path = req.headers[":path"] as string;
      seen.topic = req.headers["apns-topic"] as string;
      req.on("data", (chunk: Buffer) => (seen.body += chunk.toString()));
      req.on("end", () => {
        res.writeHead(410);
        res.end(JSON.stringify({ reason: "Unregistered" }));
      });
    });
    await new Promise<void>((resolve) => server!.listen(0, "127.0.0.1", resolve));
    const { port } = server.address() as AddressInfo;
    const transport = http2Transport();

    const answer = await transport({
      origin: `http://127.0.0.1:${port}`, path: "/3/device/abc", headers: { "apns-topic": "com.shellx.dev" }, body: "{}",
    });

    expect(answer).toEqual({ status: 410, body: JSON.stringify({ reason: "Unregistered" }) });
    expect(seen).toEqual({ path: "/3/device/abc", topic: "com.shellx.dev", body: "{}" });
    transport.close();
  });

  it("rejects with apns_timeout when APNs never answers", async () => {
    server = createServer(() => { /* never respond */ });
    await new Promise<void>((resolve) => server!.listen(0, "127.0.0.1", resolve));
    const { port } = server.address() as AddressInfo;
    const transport = http2Transport({ timeoutMs: 100 });
    try {
      await expect(Promise.race([
        transport({ origin: `http://127.0.0.1:${port}`, path: "/3/device/abc", headers: {}, body: "{}" }),
        new Promise((_, reject) => setTimeout(() => reject(new Error("transport hung")), 3_000)),
      ])).rejects.toThrow("apns_timeout");
    } finally {
      transport.close();
      server.closeAllConnections();
    }
  });
});

describe("loadApns", () => {
  const files = { "/secrets/apns.p8": privateKey };
  const readFile = (path: string) => {
    const text = (files as Record<string, string>)[path];
    if (text === undefined) throw Object.assign(new Error("missing"), { code: "ENOENT" });
    return text;
  };

  it("is on with the key file, key id and team id", () => {
    const setup = loadApns({ APNS_KEY_PATH: "/secrets/apns.p8", APNS_KEY_ID: "KEY1234567", APNS_TEAM_ID: "TEAM123456" }, { readFile });
    expect(setup.gateway).toBeInstanceOf(ApnsClient);
  });

  it.each([
    [{}, "not_configured"],
    [{ APNS_KEY_PATH: "/secrets/apns.p8", APNS_KEY_ID: "KEY1234567" }, "not_configured"],
    [{ APNS_KEY_PATH: "/secrets/missing.p8", APNS_KEY_ID: "KEY1234567", APNS_TEAM_ID: "TEAM123456" }, "unreadable"],
  ] as const)("is off for %j (%s)", (env, reason) => {
    expect(loadApns(env, { readFile })).toEqual({ gateway: null, reason });
  });

  it("is off for a file that is not a private key", () => {
    files["/secrets/apns.p8" as keyof typeof files] = "not a key";
    const setup = loadApns({ APNS_KEY_PATH: "/secrets/apns.p8", APNS_KEY_ID: "K", APNS_TEAM_ID: "T" }, { readFile });
    expect(setup).toEqual({ gateway: null, reason: "invalid" });
  });
});
