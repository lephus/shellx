# Compile-check image for the ShellX Windows app (x86_64-pc-windows-msvc) on an x86_64 or
# arm64 Linux host (Docker on this Mac). Used by scripts/shellx/check-windows-build.sh; runs
# check-in-container.sh. The installer image is Dockerfile; this one has no wine, msitools,
# xvfb, Inno Setup or fxc.exe, because the check uses cargo's dev profile, in which gpui
# compiles no shaders (the --release check uses fxc-standin.sh, which compiles none either).
#
#   rustc + cargo-xwin: MSVC CRT and Windows SDK libs via xwin
#   clang/lld/llvm 18: clang-cl, lld-link, llvm-lib, llvm-rc for cc-rs, rustc and embed-resource
#   zig: libghostty-vt
FROM ubuntu:24.04

ARG RUST_VERSION=1.95.0
ARG ZIG_VERSION=0.16.0
ARG CARGO_XWIN_VERSION=0.23.1

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git python3 build-essential pkg-config \
      clang-18 lld-18 llvm-18 libclang-18-dev \
 && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_INSTALL_ROOT=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/lib/llvm-18/bin:/opt/zig:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | CARGO_HOME=/opt/cargo sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION" --no-modify-path \
 && CARGO_HOME=/opt/cargo rustup target add x86_64-pc-windows-msvc \
 && rustc --version

# uname -m is x86_64 or aarch64, the names both release pages use.
RUN arch="$(uname -m)" \
 && url="https://github.com/rust-cross/cargo-xwin/releases/download/v${CARGO_XWIN_VERSION}/cargo-xwin-v${CARGO_XWIN_VERSION}.${arch}-unknown-linux-musl.tar.gz" \
 && if curl -sfIL "$url" >/dev/null; then \
      curl -sSfL -o /tmp/xwin.tgz "$url" \
      && tar -xzf /tmp/xwin.tgz -C /opt/cargo/bin \
      && rm /tmp/xwin.tgz; \
    else \
      CARGO_HOME=/tmp/cargo-install cargo install cargo-xwin --version "$CARGO_XWIN_VERSION" --locked \
      && rm -rf /tmp/cargo-install; \
    fi \
 && cargo-xwin --version

RUN arch="$(uname -m)" \
 && curl -sSfL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${arch}-linux-${ZIG_VERSION}.tar.xz" \
 && mkdir /opt/zig \
 && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
 && rm /tmp/zig.tar.xz \
 && zig version

COPY llvm-rc.sh zig-libc-msvc.sh check-in-container.sh fxc-standin.sh /opt/winbuild/
RUN chmod +x /opt/winbuild/*.sh

# Caches live on the shellx-wincheck-cache volume at /cache. XWIN_INCLUDE_DEBUG_SYMBOLS keeps
# the CRT .pdb files next to the .lib files: lld-link otherwise warns (LNK4099) about
# libcpmt.amd64.pdb when zig links ghostty-vt.dll, and zig build fails on any LLD stderr.
ENV CARGO_HOME=/cache/cargo \
    XWIN_CACHE_DIR=/cache/xwin \
    XWIN_ARCH=x86_64 \
    XWIN_INCLUDE_DEBUG_SYMBOLS=true \
    ZIG_GLOBAL_CACHE_DIR=/cache/zig \
    XWIN_ACCEPT_LICENSE=1 \
    RC_x86_64_pc_windows_msvc=/opt/winbuild/llvm-rc.sh
WORKDIR /src
