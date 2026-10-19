import Foundation

// ShellX links no Sentry SDK and sends no crash or usage telemetry. These
// entry points keep upstream call sites compiling and do nothing.

/// Formerly added a Sentry breadcrumb; a no-op in ShellX.
func sentryBreadcrumb(_ message: String, category: String = "ui", data: [String: Any]? = nil) {}

/// Formerly captured a Sentry warning event; a no-op in ShellX.
func sentryCaptureWarning(
    _ message: String,
    category: String = "ui",
    data: [String: Any]? = nil,
    contextKey: String? = nil
) {}

/// Formerly captured a Sentry error event; a no-op in ShellX.
func sentryCaptureError(
    _ message: String,
    category: String = "ui",
    data: [String: Any]? = nil,
    contextKey: String? = nil
) {}

@MainActor
func sentryStartMemoryContextRefresh() {}

@MainActor
func sentryStopMemoryContextRefresh() {}
