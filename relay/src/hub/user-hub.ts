import type { DeviceKind } from "../auth/device.js";
import type { Db } from "../db/db.js";
import { errorKind, logMeta } from "../log.js";
import {
  CloseCode, encodeError, encodePresence, MAX_FRAME_BYTES, pairingRemovedEvent, parseDataHeader, RelayErrorCode,
  withPeer,
} from "../protocol/frames.js";
import type { FrameBudgets } from "./frame-budgets.js";

/**
 * The server end of one WebSocket, as the hub uses it: a `ws` WebSocket in production, a fake in
 * unit tests. `readyState` 1 is OPEN.
 */
export interface HubSocket {
  readonly readyState: number;
  /** Bytes queued by `send` that have not been written to the network yet (`ws`'s own counter). */
  readonly bufferedAmount: number;
  send(data: Uint8Array | string): void;
  close(code: number, reason: string): void;
  terminate(): void;
}

export const SOCKET_OPEN = 1;
/** Sent to every socket when the relay shuts down (spec §4.3); clients reconnect with backoff. */
export const GOING_AWAY = 1001;
/**
 * Sent to a slow receiver (see MAX_BUFFERED_BYTES). shellx_core treats every close code other than
 * 4001/4002 as "reconnect with backoff"; the agent's replay buffer catches the device up.
 */
export const TRY_AGAIN_LATER = 1013;
/**
 * Largest backlog of unsent bytes a socket may have before the hub sends it anything more. A peer
 * that reads slower than its peers write would otherwise make the relay buffer without bound. Such
 * a receiver is closed rather than skipped: dropping frames would break the end-to-end Noise stream,
 * whose frames are authenticated in sequence.
 */
export const MAX_BUFFERED_BYTES = 4 * 1024 * 1024;

/** Identity of one connection, set by the ws route from the validated token. */
export interface ConnectionMeta {
  deviceId: string;
  kind: DeviceKind;
  /** Random per upgrade; lets `closeConnection` target this exact socket (never the client's value). */
  connId: string;
}

/** Metadata kept for each socket (the Durable Object's `serializeAttachment`, spec §4.2). */
export interface Attachment {
  device_id: string;
  kind: DeviceKind;
  conn_id: string;
  /** True once the hub itself closed this socket (4001/4002/4003/1001); its close event is then ignored. */
  closing: boolean;
}

/** What a hub needs from its registry. */
export interface HubHost {
  readonly db: Db;
  readonly now: () => number;
  readonly budgets: FrameBudgets;
  readonly shuttingDown: boolean;
  /** The account's live state, created on demand. */
  stateFor(userId: string): HubState;
  /** The account's live state if there is one (never creates it). */
  existingState(userId: string): HubState | undefined;
  /** Called when the state has no socket and no queued work left. */
  release(state: HubState): void;
}

const CLOSE_REASONS: Record<CloseCode, string> = {
  [CloseCode.replaced]: "replaced",
  [CloseCode.revoked]: "revoked",
  [CloseCode.rateLimited]: "rate_limited",
};

/**
 * The in-memory state of one account's hub (spec §4.3): its sockets and its serial queue. Every
 * operation that reads or changes it (a socket joining or closing, an incoming frame, a call from
 * a REST route) runs through the queue, in arrival order, like the Durable Object's input gate. A
 * failing operation is logged by kind and rejects its own caller only; the queue keeps going.
 * Dropped by the registry once it has no socket and no queued work; reached through `UserHub`.
 */
export class HubState {
  private readonly sockets = new Map<HubSocket, Attachment>();
  private tail: Promise<unknown> = Promise.resolve();
  private pending = 0;

  constructor(
    readonly userId: string,
    private readonly host: HubHost,
  ) {}

  /** Sockets held by this hub, including ones it is closing whose close event has not arrived yet. */
  get socketCount(): number {
    return this.sockets.size;
  }

  // ---- sockets (called by the ws route) -------------------------------------------------------

  /**
   * Adds a freshly upgraded socket. One connection per device: the newest wins, the old socket gets
   * 4001 and no offline is announced. The newcomer gets a PRESENCE snapshot of the other online
   * devices, then (for an agent) every pairing_removed tombstone; the others see it come online.
   * Rejects (with the socket untouched) if the tombstones cannot be read, so the caller can close it.
   */
  connect(socket: HubSocket, meta: ConnectionMeta): Promise<void> {
    return this.enqueue("connect", () => {
      if (socket.readyState !== SOCKET_OPEN) return; // the client left before its turn came
      if (this.host.shuttingDown) {
        safeClose(socket, GOING_AWAY, "going away");
        return;
      }
      const tombstones = this.tombstonesOf(meta.deviceId); // may throw: nothing has changed yet
      for (const old of this.socketsOf(meta.deviceId)) this.closeSocket(old, CloseCode.replaced);
      // The device's frame budget is deliberately NOT reset here (see FrameBudgets).
      this.sockets.set(socket, { device_id: meta.deviceId, kind: meta.kind, conn_id: meta.connId, closing: false });
      for (const other of this.liveDeviceIds()) {
        if (other !== meta.deviceId) this.sendTo(socket, encodePresence(other, true));
      }
      this.broadcast(encodePresence(meta.deviceId, true), meta.deviceId);
      for (const row of tombstones) {
        this.sendTo(socket, pairingRemovedEvent(meta.deviceId, row.mobile_id, row.pairing_id));
      }
    });
  }

  /** A binary relay frame (or any text other than "ping", which the ws route answers itself). */
  receive(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    void this.enqueue("frame", () => this.handleFrame(socket, data));
  }

  /** The ws route found `socket` over the backlog cap while answering a ping: close it (1013). */
  slowReceiver(socket: HubSocket): void {
    void this.enqueue("slow_receiver", () => this.dropSlowReceiver(socket));
  }

  /** The socket's close event: forget it and announce the device offline unless the hub closed it. */
  disconnected(socket: HubSocket): void {
    void this.enqueue("close", () => {
      const me = this.sockets.get(socket);
      if (me === undefined) return;
      this.sockets.delete(socket);
      if (!me.closing) this.markOffline(me.device_id);
    });
  }

  // ---- calls from REST routes (the former Durable Object RPC, spec §10.4) --------------------

  /** Device ids that currently have a live connection. */
  online(): Promise<string[]> {
    return this.enqueue("online", () => this.liveDeviceIds());
  }

  /** Closes every connection of `deviceIds` with `code` and announces them offline. */
  disconnect(deviceIds: string[], code: CloseCode): Promise<void> {
    return this.enqueue("disconnect", () => this.disconnectNow(deviceIds, code));
  }

  /**
   * Closes every live socket except those of `exceptDeviceId` with `code`: called after a password
   * change commits. Uses the hub's own live list at the moment it runs, not a list read earlier.
   */
  disconnectAllExcept(exceptDeviceId: string, code: CloseCode): Promise<void> {
    return this.enqueue("disconnect_all_except", () =>
      this.disconnectNow(this.liveDeviceIds().filter((id) => id !== exceptDeviceId), code),
    );
  }

  /**
   * Records the pairing_removed tombstone for the agent (always, even when it looks online: a live
   * socket can be silently dead), then sends the EVENT to both devices if connected. One tombstone
   * per (agent, mobile), keeping the newest pairing id; replayed on every connect of the agent until
   * `admitPairing` (newer id), `purgeAgent` (logout) or `purgeAll` (account deletion) removes it.
   */
  notifyPairingRemoved(agentId: string, mobileId: string, pairingId: string): Promise<void> {
    return this.enqueue("notify_pairing_removed", () => {
      this.host.db.run(
        `INSERT INTO pending_pairing_removed (user_id, agent_id, mobile_id, pairing_id) VALUES (?, ?, ?, ?)
         ON CONFLICT (agent_id, mobile_id) DO UPDATE SET pairing_id = excluded.pairing_id
         WHERE excluded.pairing_id > pending_pairing_removed.pairing_id`,
        this.userId,
        agentId,
        mobileId,
        pairingId,
      );
      const frame = pairingRemovedEvent(agentId, mobileId, pairingId);
      for (const socket of this.socketsOf(agentId)) this.sendTo(socket, frame);
      if (mobileId !== agentId) for (const socket of this.socketsOf(mobileId)) this.sendTo(socket, frame);
    });
  }

  /**
   * May pairing `pairingId` of (agent, mobile) be recorded? False when the tombstone's id is the
   * same or newer (kept); otherwise an older tombstone is deleted and the answer is true. Check and
   * delete run in one queued operation, so no notifyPairingRemoved can interleave.
   */
  admitPairing(agentId: string, mobileId: string, pairingId: string): Promise<boolean> {
    return this.enqueue("admit_pairing", () => {
      const tombstone = this.host.db.get<{ pairing_id: string }>(
        "SELECT pairing_id FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ? AND mobile_id = ?",
        this.userId,
        agentId,
        mobileId,
      );
      if (tombstone === undefined) return true;
      if (tombstone.pairing_id >= pairingId) return false;
      this.host.db.run(
        "DELETE FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ? AND mobile_id = ?",
        this.userId,
        agentId,
        mobileId,
      );
      return true;
    });
  }

  /** Deletes every tombstone of one agent (its logout). Returns the number of rows removed. */
  purgeAgent(agentId: string): Promise<number> {
    return this.enqueue("purge_agent", () =>
      this.host.db.run("DELETE FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ?", this.userId, agentId)
        .changes,
    );
  }

  /** Deletes every tombstone of the account. Returns the number of rows removed. */
  purgeAll(): Promise<number> {
    return this.enqueue("purge_all", () =>
      this.host.db.run("DELETE FROM pending_pairing_removed WHERE user_id = ?", this.userId).changes,
    );
  }

  /** Account deletion: closes whatever is live right now with 4002, then purges the tombstones. */
  closeAccount(): Promise<void> {
    return this.enqueue("close_account", () => {
      this.disconnectNow(this.liveDeviceIds(), CloseCode.revoked);
      this.host.db.run("DELETE FROM pending_pairing_removed WHERE user_id = ?", this.userId);
    });
  }

  /**
   * Closes the one socket whose connection id is `connId`, if still live; a no-op if that exact
   * connection is already gone (replaced by a newer connection of the same device, for example).
   * Used by the ws route's post-upgrade token re-check.
   */
  closeConnection(connId: string, code: CloseCode): Promise<void> {
    return this.enqueue("close_connection", () => {
      for (const [socket, me] of this.sockets) {
        if (me.conn_id === connId && isLive(socket, me)) {
          this.closeSocket(socket, code);
          this.markOffline(me.device_id);
          return;
        }
      }
    });
  }

  /** Shutdown: closes every socket with 1001 "going away". */
  goAway(): Promise<void> {
    return this.enqueue("go_away", () => {
      for (const [socket, me] of this.sockets) {
        if (me.closing) continue;
        me.closing = true;
        safeClose(socket, GOING_AWAY, "going away");
      }
    });
  }

  /** Last step of a shutdown that ran out of time: drops every socket without a close handshake. */
  terminateAll(): void {
    for (const socket of this.sockets.keys()) {
      try {
        socket.terminate();
      } catch {
        // already gone
      }
    }
  }

  /** Resolves once every operation queued so far has run. */
  idle(): Promise<void> {
    return this.tail.then(() => undefined);
  }

  // ---- internals ------------------------------------------------------------------------------

  private enqueue<T>(op: string, task: () => T): Promise<T> {
    this.pending++;
    const result = this.tail.then(task);
    this.tail = result.then(
      () => this.settle(),
      (err: unknown) => {
        logMeta("hub_op_failed", { op, error: errorKind(err) });
        this.settle();
      },
    );
    return result;
  }

  private settle(): void {
    this.pending--;
    this.releaseIfIdle();
  }

  /** Hands the state back to the registry when it holds no socket and has no queued work. */
  releaseIfIdle(): void {
    if (this.pending === 0 && this.sockets.size === 0) this.host.release(this);
  }

  private handleFrame(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    const me = this.sockets.get(socket);
    if (me === undefined || me.closing) return;

    if (!this.host.budgets.take(me.device_id)) {
      safeSend(socket, encodeError(RelayErrorCode.rateLimited));
      this.closeSocket(socket, CloseCode.rateLimited);
      logMeta("ws_rate_limited", { device_id: me.device_id });
      this.markOffline(me.device_id);
      return;
    }
    if (typeof data === "string") {
      this.sendTo(socket, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const frame = data instanceof Uint8Array ? data : new Uint8Array(data);
    const header = parseDataHeader(frame);
    if (frame.length > MAX_FRAME_BYTES) {
      this.sendTo(socket, encodeError(RelayErrorCode.frameTooLarge, header?.peer, header?.channel));
      logMeta("ws_frame_too_large", { device_id: me.device_id, size: frame.length });
      return;
    }
    if (header === null) {
      this.sendTo(socket, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const targets = this.socketsOf(header.peer);
    if (targets.length === 0) {
      this.sendTo(socket, encodeError(RelayErrorCode.peerOffline, header.peer, header.channel));
      return;
    }
    const routed = withPeer(frame, me.device_id);
    for (const target of targets) this.sendTo(target, routed);
  }

  private disconnectNow(deviceIds: string[], code: CloseCode): void {
    for (const deviceId of new Set(deviceIds)) {
      const sockets = this.socketsOf(deviceId);
      if (sockets.length === 0) continue;
      for (const socket of sockets) this.closeSocket(socket, code);
      this.markOffline(deviceId);
    }
  }

  private tombstonesOf(deviceId: string): { mobile_id: string; pairing_id: string }[] {
    return this.host.db.all<{ mobile_id: string; pairing_id: string }>(
      "SELECT mobile_id, pairing_id FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ? ORDER BY rowid",
      this.userId,
      deviceId,
    );
  }

  /** Marks the socket as closed by the hub, then closes it with `code`. */
  private closeSocket(socket: HubSocket, code: CloseCode): void {
    const me = this.sockets.get(socket);
    if (me === undefined || me.closing) return;
    me.closing = true;
    safeClose(socket, code, CLOSE_REASONS[code]);
  }

  /**
   * Announces offline and records last_seen_at, unless the device still has a live socket (it just
   * reconnected). Callers mark the departing socket as closing (or forget it) first.
   */
  private markOffline(deviceId: string): void {
    if (this.socketsOf(deviceId).length > 0) return;
    this.broadcast(encodePresence(deviceId, false), deviceId);
    try {
      this.host.db.run("UPDATE devices SET last_seen_at = ? WHERE id = ?", this.host.now(), deviceId);
    } catch {
      // Best-effort bookkeeping: a database error must not stop routing/presence.
      logMeta("last_seen_write_failed", { device_id: deviceId });
    }
  }

  /** Open, not-being-closed sockets of one device (normally zero or one). */
  private socketsOf(deviceId: string): HubSocket[] {
    const result: HubSocket[] = [];
    for (const [socket, me] of this.sockets) if (me.device_id === deviceId && isLive(socket, me)) result.push(socket);
    return result;
  }

  private liveDeviceIds(): string[] {
    const ids = new Set<string>();
    for (const [socket, me] of this.sockets) if (isLive(socket, me)) ids.add(me.device_id);
    return [...ids];
  }

  private broadcast(frame: Uint8Array, exceptDeviceId: string): void {
    for (const [socket, me] of this.sockets) {
      if (me.device_id !== exceptDeviceId && isLive(socket, me)) this.sendTo(socket, frame);
    }
  }

  /**
   * Every frame the hub sends goes through here: it is dropped, and the socket closed with 1013 and
   * announced offline, when the socket already has more than MAX_BUFFERED_BYTES waiting to go out.
   */
  private sendTo(socket: HubSocket, frame: Uint8Array): void {
    if (isSlow(socket)) this.dropSlowReceiver(socket);
    else safeSend(socket, frame);
  }

  private dropSlowReceiver(socket: HubSocket): void {
    const me = this.sockets.get(socket);
    if (me === undefined || !isLive(socket, me)) return;
    me.closing = true;
    safeClose(socket, TRY_AGAIN_LATER, "try again later");
    logMeta("slow_receiver", { device_id: me.device_id });
    this.markOffline(me.device_id);
  }
}

function isLive(socket: HubSocket, me: Attachment): boolean {
  return !me.closing && socket.readyState === SOCKET_OPEN;
}

function isSlow(socket: HubSocket): boolean {
  return socket.bufferedAmount > MAX_BUFFERED_BYTES;
}

function safeSend(socket: HubSocket, data: Uint8Array | string): void {
  try {
    socket.send(data);
  } catch {
    // the peer vanished between the check and the send; its close event will clean up
  }
}

function safeClose(socket: HubSocket, code: number, reason: string): void {
  try {
    socket.close(code, reason);
  } catch {
    // already closed
  }
}

/**
 * One account's hub, as routes see it: `registry.forUser(userId).<method>()` (spec §4.3). A thin
 * handle with no state of its own: every call reaches the account's live `HubState`, creating it
 * if needed, so a handle kept across an `await` can never talk to a state the registry already
 * dropped.
 */
export class UserHub {
  constructor(
    readonly userId: string,
    private readonly host: HubHost,
  ) {}

  private get state(): HubState {
    return this.host.stateFor(this.userId);
  }

  /** See `HubState.connect`. */
  connect(socket: HubSocket, meta: ConnectionMeta): Promise<void> {
    return this.state.connect(socket, meta);
  }

  receive(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    this.state.receive(socket, data);
  }

  /**
   * The text heartbeat: "pong" goes out right away, outside the queue (spec §4.2) — except to a slow
   * receiver, which is closed through the queue instead (pings are not budgeted, so a client that
   * never reads could otherwise pile up pongs without bound).
   */
  ping(socket: HubSocket): void {
    if (isSlow(socket)) this.state.slowReceiver(socket);
    else safeSend(socket, "pong");
  }

  disconnected(socket: HubSocket): void {
    this.state.disconnected(socket);
  }

  online(): Promise<string[]> {
    return this.state.online();
  }

  disconnect(deviceIds: string[], code: CloseCode): Promise<void> {
    return this.state.disconnect(deviceIds, code);
  }

  disconnectAllExcept(exceptDeviceId: string, code: CloseCode): Promise<void> {
    return this.state.disconnectAllExcept(exceptDeviceId, code);
  }

  notifyPairingRemoved(agentId: string, mobileId: string, pairingId: string): Promise<void> {
    return this.state.notifyPairingRemoved(agentId, mobileId, pairingId);
  }

  admitPairing(agentId: string, mobileId: string, pairingId: string): Promise<boolean> {
    return this.state.admitPairing(agentId, mobileId, pairingId);
  }

  purgeAgent(agentId: string): Promise<number> {
    return this.state.purgeAgent(agentId);
  }

  purgeAll(): Promise<number> {
    return this.state.purgeAll();
  }

  closeAccount(): Promise<void> {
    return this.state.closeAccount();
  }

  closeConnection(connId: string, code: CloseCode): Promise<void> {
    return this.state.closeConnection(connId, code);
  }

  /** Resolves once everything queued so far for this account has run (creates nothing). */
  idle(): Promise<void> {
    return this.host.existingState(this.userId)?.idle() ?? Promise.resolve();
  }

  /** Sockets the account's hub holds right now (0 when it has no state). */
  get socketCount(): number {
    return this.host.existingState(this.userId)?.socketCount ?? 0;
  }
}
