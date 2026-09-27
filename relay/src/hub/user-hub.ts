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
  /**
   * Sends whose write has not completed yet, successfully or not (counted by the ws route's adapter,
   * `WsHubSocket`). Each costs a few hundred bytes of heap however small its frame, which
   * `bufferedAmount` does not see.
   */
  readonly pendingSends: number;
  send(data: Uint8Array | string): void;
  close(code: number, reason: string): void;
  terminate(): void;
}

export const SOCKET_OPEN = 1;
/** Sent to every socket when the relay shuts down (spec §4.3); clients reconnect with backoff. */
export const GOING_AWAY = 1001;
/**
 * Sent to a slow receiver (see MAX_BUFFERED_BYTES and MAX_PENDING_SENDS), and to a new device over
 * MAX_LIVE_DEVICES_PER_ACCOUNT. shellx_core treats every close code other than 4001/4002 as
 * "reconnect with backoff"; the agent's replay buffer catches the device up.
 */
export const TRY_AGAIN_LATER = 1013;
/**
 * Largest backlog of unsent bytes a socket may have before the hub sends it anything more. A peer
 * that reads slower than its peers write would otherwise make the relay buffer without bound. Such
 * a receiver is closed rather than skipped: dropping frames would break the end-to-end Noise stream,
 * whose frames are authenticated in sequence.
 */
export const MAX_BUFFERED_BYTES = 4 * 1024 * 1024;
/**
 * Largest number of sends a socket may have queued before the hub sends it anything more; over
 * it, the socket is a slow receiver like one over MAX_BUFFERED_BYTES. Every queued send also pins
 * ~400 B of heap (buffers, write-queue entry, callback) that `bufferedAmount` does not count, so a
 * client that stops reading while its tiny frames draw ERROR replies (or tiny DATA frames flow to
 * it) would otherwise pin ~57 MB of heap before its backlog reached 4 MiB of payload. With this
 * cap, a stuck socket pins at most ~1024 × 400 B on top of its payload.
 */
export const MAX_PENDING_SENDS = 1024;
/**
 * How long the close handshake of any socket the hub closes (1013 slow receiver, 4001 replaced,
 * 4002 revoked, 4003 rate limited) may take before the socket is dropped outright. Its close frame
 * waits behind whatever backlog the socket has, and a socket being closed no longer counts as live
 * (nor against MAX_LIVE_DEVICES_PER_ACCOUNT), so `ws` would otherwise hold that backlog for its own
 * close timeout. shellx_core treats the resulting 1006 like the code it replaces: 4001 was already
 * replaced, 4002 reconnects into HTTP 401 (revoked), 1013 and 4003 reconnect with backoff.
 */
export const SLOW_RECEIVER_CLOSE_MS = 1000;
/**
 * A ping is still answered while the socket has at most this many unsent bytes: a phone reading
 * heavy output over a slow but healthy link keeps its heartbeat. Above it (a stuck or badly lagging
 * reader) the ping goes unanswered, so pongs can only ever pile up behind 64 KiB of backlog — with
 * pings inside the 500/s frame budget, a few MB of heap at worst — and the client's own heartbeat
 * times out instead.
 */
export const PONG_MAX_BUFFERED_BYTES = 64 * 1024;
/** Like PONG_MAX_BUFFERED_BYTES, for the number of queued sends: a ping is answered only at or below it. */
export const PONG_MAX_PENDING_SENDS = 64;
/**
 * Most devices one account may have connected at once. A new device beyond it is refused with 1013
 * "too many devices online" (shellx_core reconnects with backoff); a device that is already live
 * may always reconnect, since it replaces its own socket. Bounds what one account can pin in relay
 * memory at 16 sockets' worth of the per-socket caps above.
 */
export const MAX_LIVE_DEVICES_PER_ACCOUNT = 16;

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

/** What a queued task may return: anything but a promise (see `HubState.enqueue`). */
type SyncResult<T> = T extends PromiseLike<unknown> ? never : T;

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
  /** Sockets the hub closed (1013, 4001, 4002, 4003), dropped if their close event has not come in time. */
  private readonly dropTimers = new Map<HubSocket, NodeJS.Timeout>();
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
   * 4001 and no offline is announced. A device that is not live yet is refused with 1013 "too many
   * devices online" when the account already has MAX_LIVE_DEVICES_PER_ACCOUNT live devices; the
   * others are left untouched. Any earlier socket of the device that is still closing (a 4001,
   * 4003 or 1013 whose close event has not arrived) is terminated first, so a device reconnecting in
   * a loop never has more than one closing socket holding relay memory. The newcomer gets a PRESENCE
   * snapshot of the other online devices, then (for an agent) every pairing_removed tombstone; the
   * others see it come online. The newcomer's own snapshot skips the backlog check: the socket is
   * brand new, and an agent with more than ~1000 tombstones would otherwise trip MAX_PENDING_SENDS
   * on its own replay and be closed with 1013 on every connect. Anything sent to it later is
   * checked. Rejects (with the socket untouched) if the tombstones cannot be read, so the caller can
   * close it.
   */
  connect(socket: HubSocket, meta: ConnectionMeta): Promise<void> {
    return this.enqueue("connect", () => {
      if (socket.readyState !== SOCKET_OPEN) return; // the client left before its turn came
      if (this.host.shuttingDown) {
        safeClose(socket, GOING_AWAY, "going away");
        return;
      }
      const live = this.liveDeviceIds();
      if (!live.includes(meta.deviceId) && live.length >= MAX_LIVE_DEVICES_PER_ACCOUNT) {
        safeClose(socket, TRY_AGAIN_LATER, "too many devices online");
        logMeta("account_device_cap", { device_id: meta.deviceId });
        return;
      }
      const tombstones = this.tombstonesOf(meta.deviceId); // may throw: nothing has changed yet
      for (const [old, me] of this.sockets) {
        if (me.device_id === meta.deviceId && !isLive(old, me)) safeTerminate(old);
      }
      for (const old of this.socketsOf(meta.deviceId)) this.closeSocket(old, CloseCode.replaced);
      // The device's frame budget is deliberately NOT reset here (see FrameBudgets).
      this.sockets.set(socket, { device_id: meta.deviceId, kind: meta.kind, conn_id: meta.connId, closing: false });
      for (const other of this.liveDeviceIds()) {
        if (other !== meta.deviceId) safeSend(socket, encodePresence(other, true));
      }
      this.broadcast(encodePresence(meta.deviceId, true), meta.deviceId);
      for (const row of tombstones) {
        safeSend(socket, pairingRemovedEvent(meta.deviceId, row.mobile_id, row.pairing_id));
      }
    });
  }

  /** A binary relay frame (or any text other than "ping", which the ws route answers itself). */
  receive(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    void this.enqueue("frame", () => this.handleFrame(socket, data));
  }

  /** The ws route found `socket` over a backlog cap (bytes or sends) while answering a ping: close it (1013). */
  slowReceiver(socket: HubSocket): void {
    void this.enqueue("slow_receiver", () => this.dropSlowReceiver(socket));
  }

  /** A ping from `socket` found its device's frame budget spent: ERROR rate_limited, then 4003. */
  rateLimited(socket: HubSocket): void {
    void this.enqueue("rate_limited", () => this.dropRateLimited(socket));
  }

  /** The socket's close event: forget it and announce the device offline unless the hub closed it. */
  disconnected(socket: HubSocket): void {
    const timer = this.dropTimers.get(socket);
    if (timer !== undefined) {
      clearTimeout(timer);
      this.dropTimers.delete(socket);
    }
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
         WHERE excluded.pairing_id > pending_pairing_removed.pairing_id
           AND pending_pairing_removed.user_id = excluded.user_id`,
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

  /**
   * Shutdown: closes every socket with 1001 "going away" and records last_seen_at for the devices
   * that were still connected (their close events are ignored from now on, so markOffline never runs).
   */
  goAway(): Promise<void> {
    return this.enqueue("go_away", () => {
      const connected = this.liveDeviceIds();
      for (const [socket, me] of this.sockets) {
        if (me.closing) continue;
        me.closing = true;
        safeClose(socket, GOING_AWAY, "going away");
      }
      for (const deviceId of connected) this.recordLastSeen(deviceId);
    });
  }

  /** Last step of a shutdown that ran out of time: drops every socket without a close handshake. */
  terminateAll(): void {
    for (const socket of this.sockets.keys()) safeTerminate(socket);
  }

  /** Resolves once every operation queued so far has run. */
  idle(): Promise<void> {
    return this.tail.then(() => undefined);
  }

  // ---- internals ------------------------------------------------------------------------------

  /**
   * Runs `task` once every operation queued before it has run. The task MUST be synchronous: the
   * queue serialises tasks only up to their first `await`, so an async task would let later
   * operations run in the middle of it (the Durable Object's input gate had the same rule). The
   * `SyncResult` type refuses a task that returns a promise.
   */
  private enqueue<T>(op: string, task: () => SyncResult<T>): Promise<T> {
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
      this.dropRateLimited(socket);
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

  /**
   * Marks the socket as closed by the hub, then closes it with `code` (4001, 4002 or 4003); dropped
   * outright if its close has not completed SLOW_RECEIVER_CLOSE_MS later (see `dropLater`).
   */
  private closeSocket(socket: HubSocket, code: CloseCode): void {
    const me = this.sockets.get(socket);
    if (me === undefined || me.closing) return;
    me.closing = true;
    safeClose(socket, code, CLOSE_REASONS[code]);
    this.dropLater(socket);
  }

  /**
   * Terminates `socket` if its close event has not come SLOW_RECEIVER_CLOSE_MS from now. The timer
   * is unref'd (it never keeps the process alive) and cleared by `disconnected`.
   */
  private dropLater(socket: HubSocket): void {
    if (this.dropTimers.has(socket)) return;
    const timer = setTimeout(() => {
      this.dropTimers.delete(socket);
      safeTerminate(socket);
    }, SLOW_RECEIVER_CLOSE_MS);
    timer.unref();
    this.dropTimers.set(socket, timer);
  }

  /**
   * Announces offline and records last_seen_at, unless the device still has a live socket (it just
   * reconnected). Callers mark the departing socket as closing (or forget it) first.
   */
  private markOffline(deviceId: string): void {
    if (this.socketsOf(deviceId).length > 0) return;
    this.broadcast(encodePresence(deviceId, false), deviceId);
    this.recordLastSeen(deviceId);
  }

  /** Best-effort bookkeeping: a database error must not stop routing, presence or a shutdown. */
  private recordLastSeen(deviceId: string): void {
    try {
      this.host.db.run("UPDATE devices SET last_seen_at = ? WHERE id = ?", this.host.now(), deviceId);
    } catch (err) {
      logMeta("last_seen_write_failed", { device_id: deviceId, error: errorKind(err) });
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
   * announced offline, when the socket already has more than MAX_BUFFERED_BYTES or more than
   * MAX_PENDING_SENDS sends waiting to go out.
   */
  private sendTo(socket: HubSocket, frame: Uint8Array): void {
    if (isSlow(socket)) this.dropSlowReceiver(socket);
    else safeSend(socket, frame);
  }

  /** Over the frame budget (a frame or a ping): ERROR rate_limited, close 4003, announce offline. */
  private dropRateLimited(socket: HubSocket): void {
    const me = this.sockets.get(socket);
    if (me === undefined || me.closing) return;
    safeSend(socket, encodeError(RelayErrorCode.rateLimited));
    this.closeSocket(socket, CloseCode.rateLimited);
    logMeta("ws_rate_limited", { device_id: me.device_id });
    this.markOffline(me.device_id);
  }

  /**
   * Closes a slow receiver with 1013 and announces it offline. Its close frame waits behind the
   * backlog, so the socket is terminated if its close event has not come SLOW_RECEIVER_CLOSE_MS
   * later (see `dropLater`).
   */
  private dropSlowReceiver(socket: HubSocket): void {
    const me = this.sockets.get(socket);
    if (me === undefined || !isLive(socket, me)) return;
    me.closing = true;
    safeClose(socket, TRY_AGAIN_LATER, "try again later");
    this.dropLater(socket);
    logMeta("slow_receiver", { device_id: me.device_id });
    this.markOffline(me.device_id);
  }
}

function isLive(socket: HubSocket, me: Attachment): boolean {
  return !me.closing && socket.readyState === SOCKET_OPEN;
}

function isSlow(socket: HubSocket): boolean {
  return socket.bufferedAmount > MAX_BUFFERED_BYTES || socket.pendingSends > MAX_PENDING_SENDS;
}

/** May a ping be answered right now? Only while the socket's backlog is small in bytes and in sends. */
function mayPong(socket: HubSocket): boolean {
  return socket.bufferedAmount <= PONG_MAX_BUFFERED_BYTES && socket.pendingSends <= PONG_MAX_PENDING_SENDS;
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

/** Drops the connection without a close handshake; its close event still reaches `disconnected`. */
function safeTerminate(socket: HubSocket): void {
  try {
    socket.terminate();
  } catch {
    // already gone
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
   * The text heartbeat of `deviceId` (the ws route's validated device): "pong" goes out right away,
   * outside the queue (spec §4.2). A ping spends one frame of the device's 500 frames/s budget like
   * any frame; over it, the socket gets ERROR rate_limited and 4003 through the queue. A pong is
   * sent while at most PONG_MAX_BUFFERED_BYTES (64 KiB) and at most PONG_MAX_PENDING_SENDS (64)
   * sends wait to go out, so a slow but healthy link keeps its heartbeat; above either, the ping
   * goes unanswered, so a client that stops reading cannot pile up pongs (each costs far more heap
   * than the 4 bytes `bufferedAmount` counts for it) and its own heartbeat fails on the stuck socket
   * instead. A socket over the 4 MiB or 1024-send cap is closed with 1013 through the queue.
   */
  ping(socket: HubSocket, deviceId: string): void {
    if (socket.readyState !== SOCKET_OPEN) return; // being closed: nothing more to answer
    if (!this.host.budgets.take(deviceId)) this.state.rateLimited(socket);
    else if (isSlow(socket)) this.state.slowReceiver(socket);
    else if (mayPong(socket)) safeSend(socket, "pong");
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
