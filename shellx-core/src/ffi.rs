//! The K3 C entry point. Output is never NULL; free it with `shellx_core_free`.

use crate::{Core, CoreError, envelope};
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::OnceLock;

static CORE: OnceLock<Core> = OnceLock::new();

fn into_c(s: String) -> *mut c_char {
    // Envelope JSON never contains interior NULs (serde escapes them).
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"error":{"code":"panic","message":"nul in output"}}"#).unwrap())
        .into_raw()
}

fn err_env(code: &str, message: &str) -> String {
    envelope::to_envelope(Err(CoreError::new(code, message)))
}

/// # Safety
/// `method` and `json_in` must each be NULL or a valid NUL-terminated string.
/// The returned pointer is never NULL and must be released with `shellx_core_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn shellx_core_call(method: *const c_char, json_in: *const c_char) -> *mut c_char {
    let out = catch_unwind(AssertUnwindSafe(|| {
        if method.is_null() || json_in.is_null() {
            return err_env("invalid_params", "method and json_in must not be NULL");
        }
        // SAFETY: non-NULL, caller guarantees NUL termination.
        let (m, j) = unsafe { (CStr::from_ptr(method), CStr::from_ptr(json_in)) };
        let (Ok(m), Ok(j)) = (m.to_str(), j.to_str()) else {
            return err_env("invalid_json", "input is not valid UTF-8");
        };
        CORE.get_or_init(Core::new).call_json(m, j)
    }))
    .unwrap_or_else(|_| err_env("panic", "internal error"));
    into_c(out)
}

/// # Safety
/// `ptr` must be NULL or a pointer returned by `shellx_core_call`, freed at most once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn shellx_core_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        // SAFETY: allocated by CString::into_raw in `into_c`.
        drop(unsafe { CString::from_raw(ptr) });
    }
}
