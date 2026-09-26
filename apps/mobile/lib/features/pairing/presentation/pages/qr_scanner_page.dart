import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/pairing/presentation/controllers/qr_scanner_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Builds the camera view; tests replace it with a fake scanner.
typedef ScannerViewBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

Widget cameraScannerView(BuildContext context, ValueChanged<String> onCode) => _CameraScanner(onCode: onCode);

/// Spec §9.2 #3 and the design's "Ghép nối bằng mã QR": camera with a framed target and a card
/// saying where the code is; a failure sheet with "Quét lại"; a success screen with
/// "Mở terminal" / "Về danh sách máy".
@RoutePage()
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key, this.scannerBuilder = cameraScannerView});

  final ScannerViewBuilder scannerBuilder;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final QrScannerController _controller = getIt<QrScannerController>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Fire-and-forget: [MobileScanner.onDetect] cannot await it. [QrScannerController.onCode]
  /// never throws — every failure becomes the failure sheet, and a result arriving after the
  /// page closed is dropped.
  void _onCode(String raw) => unawaited(_controller.onCode(raw, S.of(context)));

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final step = _controller.step.value;
      if (step is Paired) return _PairedView(step: step);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF05090A),
          body: Stack(
            fit: StackFit.expand,
            children: [
              widget.scannerBuilder(context, _onCode),
              const _ScanFrame(),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _RoundButton(
                          tooltip: S.of(context).actionClose,
                          icon: Icons.close,
                          onTap: () => context.router.maybePop(),
                        ),
                      ),
                    ),
                    Text(
                      S.of(context).scannerTitle,
                      style: context.typo.heading20.heavy.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    const _WhereIsTheCode(),
                  ],
                ),
              ),
              if (step is Pairing) const _PairingOverlay(),
              if (step is PairingFailed) _FailureSheet(message: step.message, onScanAgain: _controller.scanAgain),
            ],
          ),
        ),
      );
    });
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x24FFFFFF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 44, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}

/// The 250 pt target with rounded corners and the moving cyan scan line.
class _ScanFrame extends StatefulWidget {
  const _ScanFrame();

  @override
  State<_ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<_ScanFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The design's `prefers-reduced-motion`: a still line when the system asks for less motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _line.stop();
    } else if (!_line.isAnimating) {
      _line.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 250,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _CornersPainter())),
            AnimatedBuilder(
              animation: _line,
              builder: (context, _) => Positioned(
                left: 14,
                right: 14,
                top: 14 + 216 * _line.value,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: TerminalColors.cyan,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: const [BoxShadow(color: TerminalColors.cyan, blurRadius: 14)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 46.0;
    const radius = 22.0;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    for (final (corner, dx, dy) in [
      (Offset.zero, 1.0, 1.0),
      (Offset(w, 0), -1.0, 1.0),
      (Offset(0, h), 1.0, -1.0),
      (Offset(w, h), -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * arm)
        ..lineTo(corner.dx, corner.dy + dy * radius)
        ..quadraticBezierTo(corner.dx, corner.dy, corner.dx + dx * radius, corner.dy)
        ..lineTo(corner.dx + dx * arm, corner.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "Mã nằm trên máy tính của bạn" and where to find it on macOS and Windows.
class _WhereIsTheCode extends StatelessWidget {
  const _WhereIsTheCode();

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final menu = strings.pairPhoneMenuItem;
    final body = strings.scannerCardBody(menu).split(menu);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xDB10181B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.scannerCardTitle, style: context.typo.subHeader15.bold.copyWith(color: Colors.white)),
          8.sizedHeight,
          Text.rich(
            TextSpan(
              style: context.typo.paragraph.copyWith(color: const Color(0xFFDFE8EA)),
              children: [
                TextSpan(text: body.first),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(5)),
                    child: Text(
                      menu,
                      style: const TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: 12.5, color: Colors.white),
                    ),
                  ),
                ),
                if (body.length > 1) TextSpan(text: body.last),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingOverlay extends StatelessWidget {
  const _PairingOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            12.sizedHeight,
            Text(S.of(context).scannerPairing, style: context.typo.subHeader.copyWith(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// Design "Mã sai hoặc hết hạn": the camera blurs behind a sheet with the spec message.
class _FailureSheet extends StatelessWidget {
  const _FailureSheet({required this.message, required this.onScanAgain});

  final String message;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: ColoredBox(color: colors.scrim),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(3)),
                  ),
                  14.sizedHeight,
                  const StatusCircle(icon: Icons.warning_amber_rounded, tone: StatusTone.error),
                  14.sizedHeight,
                  Text(strings.pairingFailedTitle, style: context.typo.heading20.heavy),
                  8.sizedHeight,
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
                  ),
                  16.sizedHeight,
                  AppButton(title: strings.scanAgain, width: double.infinity, onTap: onScanAgain),
                  4.sizedHeight,
                  AppButton(
                    title: strings.actionClose,
                    width: double.infinity,
                    height: 44,
                    backgroundColor: Colors.transparent,
                    textColor: colors.primary,
                    onTap: () => context.router.maybePop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Design "Ghép nối xong".
class _PairedView extends StatelessWidget {
  const _PairedView({required this.step});

  final Paired step;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              const StatusCircle(icon: Icons.check),
              16.sizedHeight,
              Text(strings.pairingSucceeded, style: context.typo.heading26.heavy),
              12.sizedHeight,
              HighlightedText(
                strings.pairingSucceededBody(step.machineName),
                parts: {step.machineName: null},
                textAlign: TextAlign.center,
                style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
                partStyle: context.typo.subHeader15.bold.copyWith(color: colors.primaryText),
              ),
              const Spacer(),
              AppButton(
                title: strings.openTerminal,
                width: double.infinity,
                onTap: () =>
                    context.router.replace(TerminalRoute(agentId: step.agentId, machineName: step.machineName)),
              ),
              4.sizedHeight,
              AppButton(
                title: strings.backToMachines,
                width: double.infinity,
                backgroundColor: Colors.transparent,
                textColor: colors.primary,
                onTap: () => context.router.maybePop(step.agentId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  // Every detection is delivered: with `noDuplicates` the Android plugin drops a code equal to
  // the last one, so "Quét lại" after a failed pairing could never scan the same code again.
  // [QrScannerController.onCode] already ignores codes unless it is scanning.
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _restartAfterPermission);
  }

  /// `MobileScanner` does not restart a controller it was given, and its own lifecycle handling
  /// skips a camera without permission anyway: after the user grants the permission in the
  /// phone's Settings and comes back, start the camera here. Starting may fail again (still
  /// denied); the error builder then keeps showing the notice.
  void _restartAfterPermission() {
    if (_scanner.value.error?.errorCode != MobileScannerErrorCode.permissionDenied) return;
    unawaited(
      _scanner.start().catchError((Object error) {
        if (kDebugMode) debugPrint('Camera restart failed: ${error.runtimeType}');
      }),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return MobileScanner(
      controller: _scanner,
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw != null) widget.onCode(raw);
      },
      errorBuilder: (context, error) {
        final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    denied ? strings.scannerCameraDenied : strings.scannerCameraError,
                    textAlign: TextAlign.center,
                    style: context.typo.subHeader.copyWith(color: Colors.white),
                  ),
                  if (denied) ...[
                    16.sizedHeight,
                    AppButton(title: strings.openSettings, onTap: () => getIt<ExternalLinks>().openAppSettings()),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
