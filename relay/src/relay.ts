import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import type { Duplex } from "node:stream";
import { createAdaptorServer } from "@hono/node-server";
import { type ServerOptions, WebSocketServer } from "ws";
import { createApp, type AppDeps } from "./app.js";
import { errorKind, logMeta } from "./log.js";

/**
 * Largest WebSocket message `ws` will read (Cloudflare's limit was also 1 MiB). Frames above
 * MAX_FRAME_BYTES (64 KiB) up to this size still reach the hub and get ERROR frame_too_large;
 * anything larger closes the socket with 1009.
 */
export const MAX_WS_MESSAGE_BYTES = 1024 * 1024;

/**
 * `ws`'s own wait for a close handshake before it destroys the socket (its default is 30 s). A
 * backstop for closes the hub does not drop itself after 1 s (SLOW_RECEIVER_CLOSE_MS): 1001 on
 * shutdown, 1011 from the ws route, 1013 for a device over the per-account cap. A close frame stuck
 * behind a backlog would otherwise pin that backlog for 30 s.
 */
export const WS_CLOSE_TIMEOUT_MS = 2000;

/** Shutdown waits at most this long for sockets to close and requests to finish (spec §4.3). */
export const SHUTDOWN_GRACE_MS = 5000;

/** How long a refused upgrade's socket may stay open after our answer before it is destroyed. */
export const REFUSED_UPGRADE_LINGER_MS = 5000;

export interface ListenOptions {
  host: string;
  /** 0 picks a free port (tests). */
  port: number;
  /** Defaults to REFUSED_UPGRADE_LINGER_MS; shorter in tests. */
  refusedUpgradeLingerMs?: number;
}

export interface RunningRelay {
  readonly server: Server;
  readonly port: number;
  /** `http://<host>:<port>` */
  readonly url: string;
  /**
   * Graceful stop (spec §4.3): stops accepting connections, closes every socket with 1001, waits
   * for in-flight requests and hub queues (at most `graceMs`), then drops whatever is left. The
   * caller closes the database afterwards.
   */
  shutdown(graceMs?: number): Promise<void>;
}

/**
 * After we answered and ended our side of a refused upgrade, the server (allowHalfOpen) keeps the
 * socket until the client closes its side. A client that never does would hold the file descriptor
 * forever, so the socket is destroyed once `ms` has passed (M4); the delay lets a well-behaved
 * client read the answer and close first, so it never sees a reset.
 */
function destroyAfterLinger(socket: Duplex, ms: number): void {
  const timer = setTimeout(() => socket.destroy(), ms).unref();
  socket.once("close", () => clearTimeout(timer));
}

/**
 * Residual R2: when a client resets the connection while its (valid) token is still being checked,
 * the socket is destroyed — and its one `close` event already emitted — before @hono/node-server
 * 2.1.1 registers `socket.once("close", reclaimWaiterOnClose)` and hands the socket to `ws`, which
 * refuses a destroyed socket without a word. The adaptor's pending waiter for that upgrade (and the
 * request context it holds) would then never be released. So once the adaptor's handler has settled,
 * a socket that had already closed by then — `ws` never takes over a closed socket — gets `close`
 * emitted on it once more, which runs the adaptor's cleanup. Never twice, and never for a socket
 * that was still open when the handler settled (its own close event is still to come).
 */
function watchEarlyClose(socket: Duplex): () => void {
  let closed = false;
  socket.once("close", () => {
    closed = true;
  });
  let reemitted = false;
  return () => {
    if (!closed || reemitted || !socket.destroyed) return;
    reemitted = true;
    socket.emit("close", false);
  };
}

/** Counts requests in flight so shutdown can wait for them. */
class Inflight {
  private count = 0;
  private waiters: (() => void)[] = [];

  async track<T>(work: () => Promise<T>): Promise<T> {
    this.count++;
    try {
      return await work();
    } finally {
      this.count--;
      if (this.count === 0) for (const resolve of this.waiters.splice(0)) resolve();
    }
  }

  idle(): Promise<void> {
    return this.count === 0 ? Promise.resolve() : new Promise((resolve) => this.waiters.push(resolve));
  }
}

/**
 * Serves the app on `listen`. @hono/node-server hands `upgrade` events for `/v1/ws` to the Hono
 * route, and completes the handshake with this `ws` server once the route validated the token.
 */
export async function startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay> {
  const app = createApp(deps);
  const inflight = new Inflight();
  const wsOptions: ServerOptions & { closeTimeout: number } = { // closeTimeout: ws 8.22, not in @types/ws 8.18
    noServer: true,
    maxPayload: MAX_WS_MESSAGE_BYTES,
    perMessageDeflate: false,
    clientTracking: false,
    // A control PING would be answered by `ws` itself, outside the hub's frame budget and backlog
    // checks: a client that stops reading could pile up pongs without bound. The heartbeat is the
    // text "ping" (spec §6.1), which the hub answers within those bounds; shellx_core sends no
    // control pings.
    autoPong: false,
    closeTimeout: WS_CLOSE_TIMEOUT_MS,
  };
  const wss = new WebSocketServer(wsOptions);
  const server = createAdaptorServer({
    fetch: (request, env) => inflight.track(async () => app.fetch(request, env)),
    websocket: { server: wss },
  }) as Server;

  // The adaptor's own `upgrade` listener only ever handles a WebSocket upgrade; any other Upgrade
  // request (e.g. `Upgrade: h2c`) is left unanswered and the socket hangs until nginx's 120s
  // timeout, or forever if the port is exposed directly — an unauthenticated way to exhaust file
  // descriptors. Answer anything that isn't a WebSocket upgrade with 400 ourselves, and delegate
  // everything else to the adaptor's listener unchanged. The adaptor relies on exactly one
  // `upgrade` listener being registered (its reject path checks `listenerCount === 1`), so we
  // replace it in place rather than adding a second one.
  const lingerMs = listen.refusedUpgradeLingerMs ?? REFUSED_UPGRADE_LINGER_MS;
  const [adaptorUpgrade] = server.listeners("upgrade");
  if (adaptorUpgrade) {
    server.removeListener("upgrade", adaptorUpgrade as (...args: unknown[]) => void);
    server.on("upgrade", (req, socket: Duplex, head) => {
      // Node removes the HTTP server's own `error` listener before emitting `upgrade`, and nothing
      // else adds one until `ws` takes the socket over: a client that resets the connection (RST)
      // after a refused upgrade, or while its token is being checked, would otherwise raise an
      // unhandled `error` event and kill the process (C1).
      socket.on("error", () => socket.destroy());
      const upgrade = req.headers.upgrade;
      if (typeof upgrade !== "string" || upgrade.toLowerCase() !== "websocket") {
        socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
        destroyAfterLinger(socket, lingerMs);
        return;
      }
      const reclaimIfClosedEarly = watchEarlyClose(socket);
      const handled = (adaptorUpgrade as (...args: unknown[]) => unknown).call(server, req, socket, head);
      void Promise.resolve(handled).then(
        () => {
          // The adaptor refused the upgrade (401, 426, 429, 500): it wrote the status and ended its side.
          if (socket.writableEnded) destroyAfterLinger(socket, lingerMs);
          reclaimIfClosedEarly();
        },
        (err: unknown) => {
          logMeta("ws_upgrade_failed", { error: errorKind(err) });
          socket.destroy();
          reclaimIfClosedEarly();
        },
      );
    });
  }

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(listen.port, listen.host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const { port } = server.address() as AddressInfo;
  const host = listen.host.includes(":") ? `[${listen.host}]` : listen.host;

  let stopping: Promise<void> | null = null;
  return {
    server,
    port,
    url: `http://${host}:${port}`,
    shutdown(graceMs = SHUTDOWN_GRACE_MS) {
      stopping ??= (async () => {
        server.close(); // no new connections; idle keep-alive connections are closed too
        server.closeIdleConnections();
        let timer: NodeJS.Timeout | undefined;
        const deadline = new Promise<void>((resolve) => {
          timer = setTimeout(resolve, graceMs);
        });
        await Promise.race([Promise.all([deps.hubs.goAway(), inflight.idle()]), deadline]);
        clearTimeout(timer);
        deps.hubs.terminateAll();
        server.closeAllConnections();
      })();
      return stopping;
    },
  };
}
