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
}

/**
 * Serves the app on `listen`. @hono/node-server hands `upgrade` events for `/v1/ws` to the Hono
 * route, and completes the handshake with this `ws` server once the route validated the token.
 */
export async function startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay> {
  const app = createApp(deps);
  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_WS_MESSAGE_BYTES,
    perMessageDeflate: false,
    clientTracking: false,
  });
  const server = createAdaptorServer({ fetch: app.fetch, websocket: { server: wss } }) as Server;
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(listen.port, listen.host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const { port } = server.address() as AddressInfo;
  const host = listen.host.includes(":") ? `[${listen.host}]` : listen.host;
  return { server, port, url: `http://${host}:${port}` };
}
