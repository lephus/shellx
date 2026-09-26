import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createAdaptorServer } from "@hono/node-server";
import { WebSocketServer } from "ws";
import { createApp, type AppDeps } from "./app.js";

/**
 * Largest WebSocket message `ws` will read (Cloudflare's limit was also 1 MiB). Frames above
 * MAX_FRAME_BYTES (64 KiB) up to this size still reach the hub and get ERROR frame_too_large;
 * anything larger closes the socket with 1009.
 */
export const MAX_WS_MESSAGE_BYTES = 1024 * 1024;

/** Shutdown waits at most this long for sockets to close and requests to finish (spec §4.3). */
export const SHUTDOWN_GRACE_MS = 5000;

export interface ListenOptions {
  host: string;
  /** 0 picks a free port (tests). */
  port: number;
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
  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_WS_MESSAGE_BYTES,
    perMessageDeflate: false,
    clientTracking: false,
  });
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
  const [adaptorUpgrade] = server.listeners("upgrade");
  if (adaptorUpgrade) {
    server.removeListener("upgrade", adaptorUpgrade as (...args: unknown[]) => void);
    server.on("upgrade", (req, socket, head) => {
      const upgrade = req.headers.upgrade;
      if (typeof upgrade !== "string" || upgrade.toLowerCase() !== "websocket") {
        socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
        return;
      }
      (adaptorUpgrade as (...args: unknown[]) => void).call(server, req, socket, head);
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
