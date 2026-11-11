# Sourced by build-in-container.sh and check-in-container.sh (needs XWIN_CACHE_DIR); exports ZIG_LIBC.
# zig (libghostty-vt links libc for its SIMD C++ code) cannot find a Windows SDK on Linux:
# point it at the CRT + SDK that cargo-xwin splats into $XWIN_CACHE_DIR/xwin.
xwin_root="$XWIN_CACHE_DIR/xwin"
cat > /tmp/zig-libc-msvc.txt <<EOF
include_dir=$xwin_root/sdk/include/ucrt
sys_include_dir=$xwin_root/crt/include
crt_dir=$xwin_root/sdk/lib/ucrt/x86_64
msvc_lib_dir=$xwin_root/crt/lib/x86_64
kernel32_lib_dir=$xwin_root/sdk/lib/um/x86_64
gcc_dir=
EOF
export ZIG_LIBC=/tmp/zig-libc-msvc.txt
