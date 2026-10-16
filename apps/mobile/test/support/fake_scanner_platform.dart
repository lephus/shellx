import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Stands in for the camera plugin behind `MobileScanner`: records every `start` with its
/// options, fails it with [startError] while that is set, and delivers codes through [detect].
///
/// Extending [MobileScannerPlatform] passes the interface's token, so it can be installed as
/// [MobileScannerPlatform.instance]; [install] restores the real one at tear-down.
class FakeScannerPlatform extends MobileScannerPlatform {
  final List<StartOptions> starts = [];

  /// Thrown by [start] instead of starting (e.g. `permissionDenied`).
  MobileScannerException? startError;
  int stops = 0;

  final StreamController<BarcodeCapture?> _barcodes = StreamController<BarcodeCapture?>.broadcast();

  /// Installs a fake as [MobileScannerPlatform.instance] until the test ends.
  static FakeScannerPlatform install(void Function(void Function()) addTearDown) {
    final previous = MobileScannerPlatform.instance;
    final fake = FakeScannerPlatform();
    MobileScannerPlatform.instance = fake;
    addTearDown(() => MobileScannerPlatform.instance = previous);
    return fake;
  }

  /// The camera sees a QR code holding [raw].
  void detect(String raw) => _barcodes.add(
    BarcodeCapture(
      barcodes: [Barcode(rawValue: raw, format: BarcodeFormat.qrCode)],
    ),
  );

  static const MobileScannerException permissionDenied = MobileScannerException(
    errorCode: MobileScannerErrorCode.permissionDenied,
  );

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream<TorchState>.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream<double>.empty();

  @override
  Widget buildCameraView() => const SizedBox.expand();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts.add(startOptions);
    final error = startError;
    if (error != null) throw error;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> pause() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> resetZoomScale() async {}

  @override
  Future<void> dispose() async {}
}
