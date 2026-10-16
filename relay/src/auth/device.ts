import { base64UrlDecode } from "./tokens.js";

export type DeviceKind = "agent" | "mobile";
export type DevicePlatform = "macos" | "windows" | "ios" | "android";

export const DEVICE_KINDS: readonly DeviceKind[] = ["agent", "mobile"];
export const DEVICE_PLATFORMS: readonly DevicePlatform[] = ["macos", "windows", "ios", "android"];
export const DEVICE_NAME_MAX_CHARS = 100;

export interface DeviceInput {
  kind: DeviceKind;
  name: string;
  platform: DevicePlatform;
  publicKey: Uint8Array; // X25519, 32 bytes
}

export function isDeviceKind(value: unknown): value is DeviceKind {
  return typeof value === "string" && (DEVICE_KINDS as readonly string[]).includes(value);
}

/** Validates `{kind, name, platform, public_key}` (spec §10.2); null when anything is off. */
export function parseDevice(value: unknown): DeviceInput | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  if (!isDeviceKind(v.kind)) return null;
  if (typeof v.platform !== "string" || !(DEVICE_PLATFORMS as readonly string[]).includes(v.platform)) return null;
  if (typeof v.name !== "string") return null;
  const name = v.name.trim();
  const nameLength = [...name].length;
  if (nameLength < 1 || nameLength > DEVICE_NAME_MAX_CHARS) return null;
  if (typeof v.public_key !== "string") return null;
  const publicKey = base64UrlDecode(v.public_key);
  if (publicKey === null || publicKey.length !== 32) return null;
  return { kind: v.kind, name, platform: v.platform as DevicePlatform, publicKey };
}
