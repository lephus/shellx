import AVFoundation

/// Whether the QR scanner can use the camera.
enum CameraAccess: Equatable {
    /// Not asked yet: the sheet asks when the scanner is about to show.
    case notDetermined
    case authorized
    /// Turned off in Settings, or restricted (Screen Time, a profile).
    case denied
    /// No camera at all (the simulator).
    case unavailable

    static func current() -> CameraAccess {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Shows the system prompt (with `NSCameraUsageDescription`) when not asked yet.
    static func request() async -> CameraAccess {
        let now = current()
        guard now == .notDetermined else { return now }
        return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    }
}
