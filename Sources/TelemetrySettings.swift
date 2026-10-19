import CmuxSettings
import Foundation

enum TelemetrySettings {
    // ShellX sends no telemetry (no Sentry, no PostHog, no third party), so
    // telemetry is off for every launch whatever `sendAnonymousTelemetry`
    // holds; Settings hides that row.
    static let enabledForCurrentLaunch = false

    /// `DisableTelemetry` (MDM) wins over the user opt-in. Frozen for the
    /// launch like the opt-in itself, so a profile pushed mid-session applies
    /// at the next launch; Settings shows the managed state immediately.
    static func resolveEnabled(userOptIn: Bool, policy: ManagedDevicePolicy) -> Bool {
        userOptIn && !policy.isEnforced(.disableTelemetry)
    }
}
