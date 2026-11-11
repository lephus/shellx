# Cross-build image for the ShellX Windows app (x86_64-pc-windows-msvc) on x86_64 Linux.
# Used by scripts/shellx/release/build-windows-cross.sh, which documents the flow and its
# differences from the CI build (.github/workflows/shellx-windows.yml).
#
#   rustc (cmux-tui/rust-toolchain.toml) + cargo-xwin: MSVC CRT and Windows SDK libs via xwin
#   clang/lld/llvm-rc 18: clang-cl, lld-link, llvm-lib, llvm-rc for cc-rs, rustc and embed-resource
#   zig (ghostty/build.zig.zon minimum_zig_version): libghostty-vt
#   wine: fxc.exe (gpui HLSL -> DXBC) and Inno Setup's ISCC.exe
FROM ubuntu:24.04

ARG RUST_VERSION=1.95.0
ARG ZIG_VERSION=0.16.0
ARG CARGO_XWIN_VERSION=0.23.1
ARG INNO_VERSION=6.7.1

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils git python3 build-essential pkg-config \
      clang-18 lld-18 llvm-18 libclang-18-dev \
      msitools xvfb xauth wine wine64 wine32:i386 \
 && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_INSTALL_ROOT=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/lib/llvm-18/bin:/opt/zig:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | CARGO_HOME=/opt/cargo sh -s -- -y --profile minimal --default-toolchain "$RUST_VERSION" --no-modify-path \
 && CARGO_HOME=/opt/cargo rustup target add x86_64-pc-windows-msvc \
 && rustc --version

RUN curl -sSfL -o /tmp/xwin.tgz \
      "https://github.com/rust-cross/cargo-xwin/releases/download/v${CARGO_XWIN_VERSION}/cargo-xwin-v${CARGO_XWIN_VERSION}.x86_64-unknown-linux-musl.tar.gz" \
 && tar -xzf /tmp/xwin.tgz -C /opt/cargo/bin \
 && rm /tmp/xwin.tgz \
 && cargo-xwin --version

RUN curl -sSfL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
 && mkdir /opt/zig \
 && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
 && rm /tmp/zig.tar.xz \
 && zig version

# Wine prefix with Inno Setup (ISCC.exe) at C:\InnoSetup. No mono/gecko prompts.
ENV WINEPREFIX=/opt/wine \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml="
RUN curl -sSfL -o /tmp/is.exe \
      "https://github.com/jrsoftware/issrc/releases/download/is-$(echo "$INNO_VERSION" | tr . _)/innosetup-${INNO_VERSION}.exe" \
 && xvfb-run -a sh -c 'wineboot -i && wine /tmp/is.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER "/DIR=C:\\InnoSetup" && wineserver -w' \
 && rm /tmp/is.exe \
 && test -f /opt/wine/drive_c/InnoSetup/ISCC.exe

# fxc.exe + d3dcompiler_47.dll from the Windows SDK "Store Apps Tools" MSI (VS 17 manifest).
COPY vsmanifest.py /opt/winbuild/vsmanifest.py
RUN mkdir -p /tmp/sdk && cd /tmp/sdk \
 && python3 -I /opt/winbuild/vsmanifest.py get . 'Windows SDK for Windows Store Apps Tools-x86_en-us\.msi$' \
 && for cab in $(msiinfo export "Windows SDK for Windows Store Apps Tools-x86_en-us.msi" Media | awk -F'\t' 'NR>3 && $4 ~ /^[^#].*\.cab/ {print $4}' | tr -d '\r'); do \
      python3 -I /opt/winbuild/vsmanifest.py get . "\\\\${cab}\$"; done \
 && msiextract -C /tmp/sdk/x "Windows SDK for Windows Store Apps Tools-x86_en-us.msi" >/dev/null \
 && fxc="$(find /tmp/sdk/x -path '*/x64/fxc.exe' | head -1)" \
 && mkdir -p /opt/fxc && cp "$fxc" "$(dirname "$fxc")/d3dcompiler_47.dll" /opt/fxc/ \
 && rm -rf /tmp/sdk vsmanifest.json \
 && ls -la /opt/fxc

COPY fxc-wine.sh llvm-rc.sh build-in-container.sh zig-libc-msvc.sh patch-gpui-build-rs.py /opt/winbuild/
RUN chmod +x /opt/winbuild/*.sh

# Caches live on the shellx-winbuild-cargo volume at /cache. XWIN_INCLUDE_DEBUG_SYMBOLS keeps
# the CRT .pdb files next to the .lib files: lld-link otherwise warns (LNK4099) about
# libcpmt.amd64.pdb when zig links ghostty-vt.dll, and zig build fails on any LLD stderr.
ENV CARGO_HOME=/cache/cargo \
    XWIN_CACHE_DIR=/cache/xwin \
    XWIN_ARCH=x86_64 \
    XWIN_INCLUDE_DEBUG_SYMBOLS=true \
    ZIG_GLOBAL_CACHE_DIR=/cache/zig \
    XWIN_ACCEPT_LICENSE=1 \
    GPUI_FXC_PATH=/opt/winbuild/fxc-wine.sh \
    RC_x86_64_pc_windows_msvc=/opt/winbuild/llvm-rc.sh
WORKDIR /src
