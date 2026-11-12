//! Console output for the flags (Ruling 29, R1 F12). The release exe is a GUI-subsystem
//! program, so cmd and PowerShell give it no console: `--version`, `--smoke*` and
//! `--diagnose` attach to the parent's console when stdout has no handle of its own. A pipe
//! or a file redirect is never replaced. cmd and PowerShell do not wait for a GUI-subsystem
//! exe, so their prompt comes back before the output (documented for support, plan review
//! M-14).

/// Attaches to the parent's console when stdout is missing, then opens `CONOUT$` for stdout
/// and stderr where they are still missing. Every failure leaves that handle as it was, and
/// prints are then dropped as before. Nothing off Windows.
pub fn attach_parent_console() {
    #[cfg(windows)]
    {
        use windows_sys::Win32::Foundation::{
            GENERIC_READ, GENERIC_WRITE, HANDLE, INVALID_HANDLE_VALUE,
        };
        use windows_sys::Win32::Storage::FileSystem::{
            CreateFileW, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
        };
        use windows_sys::Win32::System::Console::{
            ATTACH_PARENT_PROCESS, AttachConsole, GetStdHandle, STD_ERROR_HANDLE, STD_HANDLE,
            STD_OUTPUT_HANDLE, SetStdHandle,
        };

        fn missing(which: STD_HANDLE) -> bool {
            // SAFETY: a plain query of this process's standard handle.
            let handle: HANDLE = unsafe { GetStdHandle(which) };
            handle.is_null() || handle == INVALID_HANDLE_VALUE
        }

        if !missing(STD_OUTPUT_HANDLE) {
            return; // a console, a pipe or a file: keep it
        }
        // SAFETY: plain value; fails (ignored) when the parent has no console.
        unsafe { AttachConsole(ATTACH_PARENT_PROCESS) };
        let name: Vec<u16> = "CONOUT$".encode_utf16().chain(std::iter::once(0)).collect();
        for which in [STD_OUTPUT_HANDLE, STD_ERROR_HANDLE] {
            if !missing(which) {
                continue;
            }
            // SAFETY: a NUL-terminated name, null attributes and template. "CONOUT$" opens
            // the attached console's active screen buffer.
            let handle = unsafe {
                CreateFileW(
                    name.as_ptr(),
                    GENERIC_READ | GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    std::ptr::null(),
                    OPEN_EXISTING,
                    0,
                    std::ptr::null_mut(),
                )
            };
            if handle.is_null() || handle == INVALID_HANDLE_VALUE {
                continue;
            }
            // SAFETY: the handle is ours and stays open for the process's life (std reads the
            // standard handle on every write).
            unsafe { SetStdHandle(which, handle) };
        }
    }
}
