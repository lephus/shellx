# ShellX relay2: cmux-relay (GPL fork source) as a container.
# Build context = fork repo root (a git checkout, a source tarball from
# source-tarball.sh, or a git context):
#   docker build -f scripts/shellx/relay2/Dockerfile \
#     --build-arg REVISION=<40-hex sha> -t shellx-relay2:<sha> .
FROM rust:1.95.0-bookworm AS build
ARG CARGO_BUILD_JOBS=2
ENV CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS}
WORKDIR /src
COPY cmux-tui/Cargo.toml cmux-tui/Cargo.lock cmux-tui/rust-toolchain.toml ./
COPY cmux-tui/crates crates
COPY cmux-tui/bindings bindings
COPY cmux-tui/vendor vendor
COPY cmux-tui/build-support build-support
# An image only exists if the relay tests pass.
RUN cargo test -p cmux-relay --locked \
 && cargo build -p cmux-relay --locked --release

FROM debian:bookworm-slim
ARG REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/lephus/shellx-pro" \
      org.opencontainers.image.revision="${REVISION}"
COPY --from=build /src/target/release/cmux-relay /usr/local/bin/cmux-relay
USER 10001:10001
EXPOSE 8787
ENTRYPOINT ["/usr/local/bin/cmux-relay"]
CMD ["serve"]
