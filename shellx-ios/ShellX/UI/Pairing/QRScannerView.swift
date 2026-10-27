import AVFoundation
import SwiftUI
import UIKit

/// Whether the scanner can use the camera.
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

/// The back camera's live picture, reporting every QR code it reads (`AVCaptureMetadataOutput`).
/// Codes arrive on the main thread, many times a second while one is in view; the caller filters
/// them (`PairingScanFilter`). The capture stops when the view goes away.
struct QRScannerView: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.start(in: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // `layerClass` above makes this cast always succeed.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    @MainActor
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: (String) -> Void
        private let capture = CaptureSession()

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func start(in view: PreviewView) {
            guard let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device)
            else { return }
            let session = capture.session
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) {
                session.addOutput(output)
                // Delivered on the main queue, so `metadataOutput` runs on the main actor.
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
            }
            session.commitConfiguration()
            view.previewLayer.session = session
            capture.start()
        }

        func stop() {
            capture.stop()
        }

        nonisolated func metadataOutput(
            _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
            guard !codes.isEmpty else { return }
            MainActor.assumeIsolated {
                for code in codes { onCode(code) }
            }
        }
    }
}

/// The capture session, started and stopped on its own queue: `startRunning()` blocks.
private final class CaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.shellx.qr-capture")

    func start() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
}
