import { encodeTextMap } from "./cbor.js";
import { NIL_UUID, uuidFromBytes, uuidToBytes } from "./uuid.js";

export const RELAY_PROTOCOL_VERSION = 1;
export const MAX_FRAME_BYTES = 64 * 1024;
export const DATA_HEADER_BYTES = 26;
export const CHANNEL_ID_BYTES = 8;

export const FrameType = { data: 0x01, presence: 0x02, error: 0x03, event: 0x04 } as const;

export const RelayErrorCode = { peerOffline: 1, frameTooLarge: 2, rateLimited: 3, badFrame: 4 } as const;
export type RelayErrorCode = (typeof RelayErrorCode)[keyof typeof RelayErrorCode];

export const CloseCode = { replaced: 4001, revoked: 4002, rateLimited: 4003 } as const;
export type CloseCode = (typeof CloseCode)[keyof typeof CloseCode];

export const ZERO_CHANNEL = new Uint8Array(CHANNEL_ID_BYTES);

export interface DataHeader {
  peer: string;
  channel: Uint8Array;
}

/** Parses the header of a client → hub DATA frame; null if it is not a well-formed DATA frame. */
export function parseDataHeader(frame: Uint8Array): DataHeader | null {
  if (frame.length < DATA_HEADER_BYTES) return null;
  if (frame[0] !== RELAY_PROTOCOL_VERSION || frame[1] !== FrameType.data) return null;
  return { peer: uuidFromBytes(frame.slice(2, 18)), channel: frame.slice(18, DATA_HEADER_BYTES) };
}

/** Copy of a DATA frame with bytes [2..17] replaced by `source` (hub → destination). */
export function withPeer(frame: Uint8Array, source: string): Uint8Array {
  const out = frame.slice();
  out.set(uuidToBytes(source), 2);
  return out;
}

export function encodeData(peer: string, channel: Uint8Array, payload: Uint8Array): Uint8Array {
  if (channel.length !== CHANNEL_ID_BYTES) throw new TypeError("channel id must be 8 bytes");
  const out = new Uint8Array(DATA_HEADER_BYTES + payload.length);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.data;
  out.set(uuidToBytes(peer), 2);
  out.set(channel, 18);
  out.set(payload, DATA_HEADER_BYTES);
  return out;
}

export function encodePresence(deviceId: string, online: boolean): Uint8Array {
  const out = new Uint8Array(19);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.presence;
  out.set(uuidToBytes(deviceId), 2);
  out[18] = online ? 1 : 0;
  return out;
}

export function encodeError(
  code: RelayErrorCode,
  deviceId: string = NIL_UUID,
  channel: Uint8Array = ZERO_CHANNEL,
): Uint8Array {
  if (channel.length !== CHANNEL_ID_BYTES) throw new TypeError("channel id must be 8 bytes");
  const out = new Uint8Array(28);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.error;
  out[2] = code >> 8;
  out[3] = code & 0xff;
  out.set(uuidToBytes(deviceId), 4);
  out.set(channel, 20);
  return out;
}

export function encodeEvent(event: Readonly<Record<string, string>>): Uint8Array {
  const body = encodeTextMap(event);
  const out = new Uint8Array(2 + body.length);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.event;
  out.set(body, 2);
  return out;
}

/** EVENT pairing_removed for one pairing, identified by the id its agent generated (overview §4.1). */
export function pairingRemovedEvent(agentId: string, mobileId: string, pairingId: string): Uint8Array {
  return encodeEvent({ event: "pairing_removed", agent_id: agentId, mobile_id: mobileId, pairing_id: pairingId });
}
