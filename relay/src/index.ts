import { createApp } from "./app";
import type { Env } from "./env";

export { UserHub } from "./hub/user-hub";

const app = createApp();

export default {
  fetch: (request, env, ctx) => app.fetch(request, env, ctx),
} satisfies ExportedHandler<Env>;
