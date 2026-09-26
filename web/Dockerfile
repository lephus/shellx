# syntax=docker/dockerfile:1
# ShellX website image (VPS spec §4.6). Build from the repository root, because it also needs
# deploy/web/nginx.conf:  docker build -f web/Dockerfile -t shellx-web .
# `npm run build` refuses to build while a page still has the "[quốc gia]" placeholder, then runs
# the page and link checks of tests/site.test.mjs.

FROM node:22-bookworm-slim AS build
WORKDIR /web
ENV ASTRO_TELEMETRY_DISABLED=1
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM nginx:alpine AS runtime
LABEL org.opencontainers.image.source="https://github.com/lephus/shellx"
COPY deploy/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /web/dist /usr/share/nginx/html
