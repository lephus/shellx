#!/usr/bin/env bash
# GPUI_FXC_PATH for a Linux host: runs the Windows SDK fxc.exe (with its native
# d3dcompiler_47.dll) under wine. gpui's build.rs calls
#   fxc /T vs_4_1 /E quad_vertex /Fh <OUT_DIR>/quad_vs.h /Vn QUAD_VERTEX_BYTES /O3 <shader.hlsl>
# fxc reads a leading "/" as an option, so absolute Unix paths become Z:\ paths.
set -euo pipefail
fxc_dir="${SHELLX_FXC_DIR:-/opt/fxc}"
args=()
for arg in "$@"; do
  if [[ "$arg" == /*/* ]]; then
    arg="Z:${arg//\//\\}"
  fi
  args+=("$arg")
done
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="d3dcompiler_47=n;${WINEDLLOVERRIDES:-}"
exec wine "$fxc_dir/fxc.exe" "${args[@]}"
