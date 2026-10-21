import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// ShellX: the phone-handoff QR (spec §7.2), a copy of `CmxPairingQRBitmap` (CMUXMobileCore is not
/// linked for this). One pixel per module, black on white, ECC M, the ISO/IEC 18004 quiet zone of 4
/// modules baked in; callers upscale with interpolation off.
enum ShellXQRCode {
    static let quietZoneModules = 4

    /// nil when Core Image produces no code (empty or over-capacity payload).
    static func makeImage(payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        // The generator's margin is 1 module; widen it to the full quiet zone over white.
        let padding = CGFloat(quietZoneModules - 1)
        let paddedRect = output.extent.insetBy(dx: -padding, dy: -padding)
        let white = CIImage(color: .white).cropped(to: paddedRect)
        return CIContext().createCGImage(output.composited(over: white), from: paddedRect)
    }
}
