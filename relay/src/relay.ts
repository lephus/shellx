import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createAdaptorServer } from "@hono/node-server";
import { createApp, type AppDeps } from "./app.js";

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

/** Serves the app on `listen` (HTTP only for now; the WebSocket upgrade is added with the hub). */
export async function startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay> {
  const app = createApp(deps);
  const server = createAdaptorServer({ fetch: app.fetch }) as Server;
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
