//! Fault injection for integration tests (feature `test-hooks`, env var
//! `SHELLX_TERM_FAULT`). Always false in real builds.

#[cfg(feature = "test-hooks")]
pub fn hit(point: &str) -> bool {
    std::env::var("SHELLX_TERM_FAULT").is_ok_and(|value| value == point)
}

#[cfg(not(feature = "test-hooks"))]
#[inline(always)]
pub fn hit(_point: &str) -> bool {
    false
}

/// Short link timers for integration tests (`SHELLX_TERM_TIMING=fast`).
#[cfg(feature = "test-hooks")]
pub fn fast_timing() -> bool {
    std::env::var("SHELLX_TERM_TIMING").is_ok_and(|v| v == "fast")
}

#[cfg(not(feature = "test-hooks"))]
#[inline(always)]
pub fn fast_timing() -> bool {
    false
}
