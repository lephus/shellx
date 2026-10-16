# syntax=docker/dockerfile:1
# ShellX relay image (VPS spec §4.6). Build from relay/: docker build -t shellx-relay relay
# The runtime stage is built FROM the test stage's output, so an image only exists if every relay
# test passed (V6). Everything before `runtime` runs as the unprivileged `node` user (uid 1000).

FROM node:22-bookworm-slim AS deps
WORKDIR /app
RUN chown node:node /app
USER node
COPY --chown=node:node package.json package-lock.json .npmrc ./
RUN npm ci

FROM deps AS test
COPY --chown=node:node . .
RUN npm run typecheck && npm test

FROM test AS build
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime
LABEL org.opencontainers.image.source="https://github.com/lephus/shellx"
ENV NODE_ENV=production
# argon2 runs on the libuv thread pool (4 threads by default) and may hold 4 of them at once; 8
# leaves room for crypto.subtle digests and file-system work while every hash slot is busy (M8).
ENV UV_THREADPOOL_SIZE=8
WORKDIR /app
# /data is where ./data is bind-mounted (the SQLite database); it must be writable by uid 1000.
RUN mkdir -p /data && chown node:node /data
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/migrations ./migrations
USER node
EXPOSE 8080
CMD ["node", "dist/server.js"]
