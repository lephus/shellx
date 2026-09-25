import { DurableObject } from "cloudflare:workers";
import type { DeviceKind } from "../auth/device";
import type { Env } from "../env";
import { logMeta } from "../log";
import {
  CloseCode, encodeError, encodePresence, MAX_FRAME_BYTES, pairingRemovedEvent, parseDataHeader, RelayErrorCode,
  withPeer,
} from "../protocol/frames";
import { parseUuid } from "../protocol/uuid";
import { FRAMES_PER_SECOND, TokenBucket } from "./token-bucket";

/** Set by the Worker after token validation; the hub is not reachable from the Internet directly. */
export const DEVICE_ID_HEADER = "X-Shellx-Device-Id";
export const DEVICE_KIND_HEADER = "X-Shellx-Device-Kind";

/** The account's hub: exactly one per user (`idFromName(user_id)`, spec §4). */
export function hubFor(env: Env, userId: string): DurableObjectStub<UserHub> {
  return env.USER_HUB.get(env.USER_HUB.idFromName(userId));
}

/** Persisted with serializeAttachment, so it survives hibernation. */
export interface Attachment {
  device_id: string;
  kind: DeviceKind;
  /** True once the hub itself closed this socket (4001/4002/4003); its close event is then ignored. */
  closing?: boolean;
}

const CLOSE_REASONS: Record<CloseCode, string> = {
  [CloseCode.replaced]: "replaced",
  [CloseCode.revoked]: "revoked",
  [CloseCode.rateLimited]: "rate_limited",
};

/**
 * One instance per account (`idFromName(user_id)`): every device of the account connects here, so
 * frames can only ever be routed between devices of the same account.
 */
export class UserHub extends DurableObject<Env> {
  /**
   * Per-device frame budget, in memory only, keyed by device id and kept across that device's
   * reconnects (see fetch()/markOffline() below) so reconnecting cannot be used to reset it. It is
   * lost when the object hibernates, which is harmless: hibernation needs ~10 s without events,
   * after which a 500-token bucket refilling at 500/s is full anyway — exactly what a fresh bucket
   * starts with. Persisting it would cost a storage write per frame.
   */
  private readonly buckets = new Map<string, TokenBucket>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // Heartbeat is answered by the runtime without waking the object (spec §6.1).
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    // Durable (SQLite-backed), deduplicated queue of pairing_removed events pending delivery to an
    // agent: at most one row per (agent, mobile) pair, so repeated pair/unpair cycles while the
    // agent is offline collapse into a single replay. The frame is encoded at delivery time, not
    // stored, so a protocol change cannot leave stale encoded bytes behind.
    ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS pending_pairing_removed (agent_id TEXT NOT NULL, mobile_id TEXT NOT NULL, UNIQUE (agent_id, mobile_id))",
    );
  }

  async fetch(request: Request): Promise<Response> {
    const deviceId = parseUuid(request.headers.get(DEVICE_ID_HEADER));
    const kind = request.headers.get(DEVICE_KIND_HEADER);
    if (
      deviceId === null ||
      (kind !== "agent" && kind !== "mobile") ||
      request.headers.get("Upgrade")?.toLowerCase() !== "websocket"
    ) {
      return new Response("bad hub request", { status: 400 });
    }

    // One connection per device: the newest wins; the old socket gets 4001 and no offline is announced.
    for (const old of this.socketsOf(deviceId)) this.closeSocket(old, CloseCode.replaced);
    // Deliberately not resetting the device's bucket here: doing so let a client sustain more than
    // FRAMES_PER_SECOND by reconnecting (or getting itself "replaced") rapidly, each time starting
    // over with a full budget. The bucket instead persists across reconnects for as long as this
    // object stays warm; only hibernation clears it, which is harmless (see the field doc above).

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [deviceId]);
    server.serializeAttachment({ device_id: deviceId, kind } satisfies Attachment);

    for (const other of this.liveDeviceIds()) {
      if (other !== deviceId) server.send(encodePresence(other, true));
    }
    this.broadcast(encodePresence(deviceId, true), deviceId);
    this.deliverPending(server, deviceId);
    return new Response(null, { status: 101, webSocket: client });
  }

  // ---- RPC for the Worker (spec §10.4) -------------------------------------------------------

  /** Device ids that currently have a live connection. */
  online(): string[] {
    return this.liveDeviceIds();
  }

  /** Closes every connection of `deviceIds` with `code` (4002 after a password change) and announces offline. */
  async disconnect(deviceIds: string[], code: CloseCode): Promise<void> {
    for (const deviceId of new Set(deviceIds)) {
      const sockets = this.socketsOf(deviceId);
      if (sockets.length === 0) continue;
      for (const ws of sockets) this.closeSocket(ws, code);
      await this.markOffline(deviceId);
    }
  }

  /**
   * Sends EVENT pairing_removed to both devices if connected (clients handle it idempotently).
   * The event is *always* durably queued for the agent too — even when it looks live — because a
   * live socket can be silently dead (e.g. a peer that vanished without a close frame), and the
   * relay may only ever remove trust: a lost pairing_removed is unsafe, a duplicate is not (spec
   * §5.4–5.5, constraint 8). The queue is delivered again on every one of the agent's future
   * connects, right after the PRESENCE snapshot, and cleared as delivered.
   */
  notifyPairingRemoved(agentId: string, mobileId: string): void {
    const frame = pairingRemovedEvent(agentId, mobileId);
    this.ctx.storage.sql.exec(
      "INSERT OR IGNORE INTO pending_pairing_removed (agent_id, mobile_id) VALUES (?, ?)",
      agentId,
      mobileId,
    );
    for (const ws of this.socketsOf(agentId)) safeSend(ws, frame);
    if (mobileId !== agentId) for (const ws of this.socketsOf(mobileId)) safeSend(ws, frame);
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const me = attachmentOf(ws);
    if (me === null || me.closing) return;

    if (!this.takeToken(me.device_id)) {
      safeSend(ws, encodeError(RelayErrorCode.rateLimited));
      this.closeSocket(ws, CloseCode.rateLimited);
      logMeta("ws_rate_limited", { device_id: me.device_id });
      await this.markOffline(me.device_id);
      return;
    }

    if (typeof message === "string") {
      // Only "ping" is valid text, and the runtime answers it before we get here.
      safeSend(ws, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const frame = new Uint8Array(message);
    const header = parseDataHeader(frame);
    if (frame.length > MAX_FRAME_BYTES) {
      safeSend(ws, encodeError(RelayErrorCode.frameTooLarge, header?.peer, header?.channel));
      logMeta("ws_frame_too_large", { device_id: me.device_id, size: frame.length });
      return;
    }
    if (header === null) {
      safeSend(ws, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const targets = this.socketsOf(header.peer);
    if (targets.length === 0) {
      safeSend(ws, encodeError(RelayErrorCode.peerOffline, header.peer, header.channel));
      return;
    }
    const routed = withPeer(frame, me.device_id);
    for (const target of targets) safeSend(target, routed);
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    await this.socketGone(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.socketGone(ws);
  }

  // ---- helpers -------------------------------------------------------------------------------

  private deliverPending(ws: WebSocket, deviceId: string): void {
    const rows = this.ctx.storage.sql
      .exec<{ mobile_id: string }>(
        "SELECT mobile_id FROM pending_pairing_removed WHERE agent_id = ? ORDER BY rowid",
        deviceId,
      )
      .toArray();
    if (rows.length === 0) return;
    for (const row of rows) ws.send(pairingRemovedEvent(deviceId, row.mobile_id));
    this.ctx.storage.sql.exec("DELETE FROM pending_pairing_removed WHERE agent_id = ?", deviceId);
  }

  private takeToken(deviceId: string): boolean {
    const now = Date.now();
    let bucket = this.buckets.get(deviceId);
    if (bucket === undefined) {
      bucket = new TokenBucket(FRAMES_PER_SECOND, FRAMES_PER_SECOND, now);
      this.buckets.set(deviceId, bucket);
    }
    return bucket.take(now);
  }

  private async socketGone(ws: WebSocket): Promise<void> {
    const me = attachmentOf(ws);
    if (me === null || me.closing) return; // the hub closed it on purpose and already handled it
    ws.serializeAttachment({ ...me, closing: true } satisfies Attachment);
    try {
      ws.close(1000, "closed");
    } catch {
      // already closed
    }
    await this.markOffline(me.device_id);
  }

  /** Marks the socket as closed by the hub, then closes it with `code`. */
  private closeSocket(ws: WebSocket, code: CloseCode): void {
    const me = attachmentOf(ws);
    if (me === null || me.closing) return;
    ws.serializeAttachment({ ...me, closing: true } satisfies Attachment);
    try {
      ws.close(code, CLOSE_REASONS[code]);
    } catch {
      // already closed
    }
  }

  /**
   * Announces offline and records last_seen_at, unless the device still has a live socket (it just
   * reconnected). Callers mark the departing socket as `closing` first, so it is never counted.
   */
  private async markOffline(deviceId: string): Promise<void> {
    if (this.socketsOf(deviceId).length > 0) return;
    // The bucket is kept here too (see fetch()): a full disconnect+reconnect must not refill it.
    this.broadcast(encodePresence(deviceId, false), deviceId);
    try {
      await this.env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(Date.now(), deviceId).run();
    } catch {
      // Best-effort bookkeeping: a D1 outage must not stop the hub from routing/presence.
      logMeta("last_seen_write_failed", { device_id: deviceId });
    }
  }

  /** Open, not-being-closed sockets of one device (normally zero or one). */
  private socketsOf(deviceId: string): WebSocket[] {
    return this.ctx.getWebSockets(deviceId).filter(isLive);
  }

  private liveDeviceIds(): string[] {
    const ids = new Set<string>();
    for (const ws of this.ctx.getWebSockets()) {
      if (isLive(ws)) ids.add(attachmentOf(ws)!.device_id);
    }
    return [...ids];
  }

  private broadcast(frame: Uint8Array, exceptDeviceId: string): void {
    for (const ws of this.ctx.getWebSockets()) {
      if (isLive(ws) && attachmentOf(ws)!.device_id !== exceptDeviceId) safeSend(ws, frame);
    }
  }
}

function attachmentOf(ws: WebSocket): Attachment | null {
  return (ws.deserializeAttachment() as Attachment | null) ?? null;
}

function isLive(ws: WebSocket): boolean {
  const a = attachmentOf(ws);
  return a !== null && !a.closing && ws.readyState === WebSocket.OPEN;
}

function safeSend(ws: WebSocket, data: Uint8Array): void {
  try {
    ws.send(data);
  } catch {
    // the peer vanished between the check and the send; its close handler will clean up
  }
}
