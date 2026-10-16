import { describe, expect, it } from "vitest";
import { encodeTextMap } from "../src/protocol/cbor.js";
import {
  CloseCode, encodeData, encodeError, encodeEvent, encodePresence, MAX_FRAME_BYTES,
  pairingRemovedEvent, parseDataHeader, RelayErrorCode, withPeer,
} from "../src/protocol/frames.js";
import { NIL_UUID, parseUuid, parseUuidV7, uuidFromBytes, uuidToBytes, uuidV7Millis } from "../src/protocol/uuid.js";

const hex = (bytes: Uint8Array): string => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
const fromHex = (h: string): Uint8Array => Uint8Array.from(h.match(/../g)!.map((x) => Number.parseInt(x, 16)));

const A = "0123abcd-4567-4def-8123-456789abcdef";
const A_HEX = "0123abcd45674def8123456789abcdef";
const B = "fedcba98-7654-4321-8fed-cba987654321";
const B_HEX = "fedcba98765443218fedcba987654321";
const P = "c0ffee00-1234-7abc-9def-0123456789ab"; // UUIDv7-shaped
const CH = fromHex("0102030405060708");

describe("uuid", () => {
  it("round-trips in textual byte order", () => {
    expect(hex(uuidToBytes(A))).toBe(A_HEX);
    expect(uuidFromBytes(uuidToBytes(A))).toBe(A);
  });
  it("parseUuidV7 accepts only version-7 UUIDs already in canonical lower case", () => {
    const v7 = "0192d1f0-7a3b-7c4d-8e5f-0123456789ab";
    expect(parseUuidV7(v7)).toBe(v7);
    expect(parseUuidV7(v7.toUpperCase())).toBeNull(); // no silent case folding
    expect(parseUuidV7("0192D1F0-7a3b-7c4d-8e5f-0123456789ab")).toBeNull();
    expect(parseUuidV7(A)).toBeNull(); // version 4
    expect(parseUuidV7(NIL_UUID)).toBeNull();
    expect(parseUuidV7("0192d1f0-7a3b-8c4d-8e5f-0123456789ab")).toBeNull(); // version 8
    expect(parseUuidV7("not-a-uuid")).toBeNull();
    expect(parseUuidV7(7)).toBeNull();
  });
  it("uuidV7Millis reads the 48-bit unix-ms timestamp", () => {
    expect(uuidV7Millis("0192d1f0-7a3b-7c4d-8e5f-0123456789ab")).toBe(0x0192d1f07a3b);
    expect(uuidV7Millis("ffffffff-ffff-7fff-bfff-ffffffffffff")).toBe(2 ** 48 - 1);
    expect(uuidV7Millis("00000000-0000-7000-8000-000000000000")).toBe(0);
  });
  it("canonicalises to lowercase and rejects garbage", () => {
    expect(parseUuid(A.toUpperCase())).toBe(A);
    expect(parseUuid("not-a-uuid")).toBeNull();
    expect(parseUuid(42)).toBeNull();
    expect(() => uuidToBytes("nope")).toThrow(TypeError);
    expect(hex(uuidToBytes(NIL_UUID))).toBe("00".repeat(16));
  });
});

describe("cbor text map (RFC 8949 Appendix A vectors)", () => {
  it("encodes {} and a one-entry map", () => {
    expect(hex(encodeTextMap({}))).toBe("a0");
    expect(hex(encodeTextMap({ a: "b" }))).toBe("a161616162");
  });
  it("encodes the five-entry map vector", () => {
    expect(hex(encodeTextMap({ a: "A", b: "B", c: "C", d: "D", e: "E" }))).toBe(
      "a56161614161626142616361436164614461656145",
    );
  });
  it("uses UTF-8 byte length and 1-byte / 2-byte length headers", () => {
    expect(hex(encodeTextMap({ "ü": "" }))).toBe("a162c3bc60");
    expect(hex(encodeTextMap({ k: "x".repeat(24) }).slice(0, 5))).toBe("a1616b7818");
    expect(hex(encodeTextMap({ k: "y".repeat(256) }).slice(0, 6))).toBe("a1616b790100");
  });
});

describe("relay frames (overview §4.1)", () => {
  it("DATA: header layout and peer rewrite", () => {
    const frame = encodeData(B, CH, fromHex("04aabb"));
    expect(hex(frame)).toBe(`0101${B_HEX}010203040506070804aabb`);
    expect(parseDataHeader(frame)).toEqual({ peer: B, channel: CH });
    const rewritten = withPeer(frame, A);
    expect(hex(rewritten)).toBe(`0101${A_HEX}010203040506070804aabb`);
    expect(parseDataHeader(frame)?.peer).toBe(B); // original buffer untouched
  });
  it("DATA parse rejects short, wrong-version and non-DATA frames", () => {
    expect(parseDataHeader(new Uint8Array(25))).toBeNull();
    const frame = encodeData(B, CH, new Uint8Array());
    expect(frame.length).toBe(26);
    expect(parseDataHeader(frame)).not.toBeNull();
    const v2 = frame.slice();
    v2[0] = 2;
    expect(parseDataHeader(v2)).toBeNull();
    const presence = frame.slice();
    presence[1] = 0x02;
    expect(parseDataHeader(presence)).toBeNull();
  });
  it("PRESENCE is 19 bytes", () => {
    expect(hex(encodePresence(A, true))).toBe(`0102${A_HEX}01`);
    expect(hex(encodePresence(A, false))).toBe(`0102${A_HEX}00`);
  });
  it("ERROR is 28 bytes with a big-endian code; defaults to nil device and zero channel", () => {
    expect(hex(encodeError(RelayErrorCode.peerOffline, B, CH))).toBe(`01030001${B_HEX}0102030405060708`);
    expect(hex(encodeError(RelayErrorCode.badFrame))).toBe(`01030004${"00".repeat(24)}`);
    expect(hex(encodeError(RelayErrorCode.frameTooLarge).slice(2, 4))).toBe("0002");
    expect(hex(encodeError(RelayErrorCode.rateLimited).slice(2, 4))).toBe("0003");
  });
  it("EVENT pairing_removed matches the byte-for-byte vector (4 text entries, pairing_id last)", () => {
    expect(hex(pairingRemovedEvent(A, B, P))).toBe(
      "0104a4656576656e746f70616972696e675f72656d6f766564686167656e745f6964782430313233616263642d34" +
        "3536372d346465662d383132332d343536373839616263646566696d6f62696c655f69647824666564636261" +
        "39382d373635342d343332312d386665642d6362613938373635343332316a70616972696e675f696478246330" +
        "6666656530302d313233342d376162632d396465662d303132333435363738396162",
    );
    expect(encodeEvent({})).toEqual(Uint8Array.from([1, 4, 0xa0]));
  });
  it("constants match the wire contract", () => {
    expect(MAX_FRAME_BYTES).toBe(65536);
    expect(CloseCode).toEqual({ replaced: 4001, revoked: 4002, rateLimited: 4003 });
    expect(RelayErrorCode).toEqual({ peerOffline: 1, frameTooLarge: 2, rateLimited: 3, badFrame: 4 });
  });
});
