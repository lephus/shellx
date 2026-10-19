/// Compile-time feature switches. Wave 2 flips `remoteMachines`.
public enum ShellXFeatures {
    public static let remoteMachines = false
    /// Upstream cmux device mirroring (DevicesFeature, MobileHostService, PresenceSettings) stays off:
    /// ShellX remote uses its own transport (W2 plan Task 13).
    public static let upstreamDeviceMirroring = false
}
