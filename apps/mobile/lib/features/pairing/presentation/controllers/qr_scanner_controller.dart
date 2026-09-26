import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/pairing/domain/pairing_flow.dart';
import 'package:shellx_mobile/shared/shared.dart';

sealed class ScannerStep {
  const ScannerStep();
}

final class Scanning extends ScannerStep {
  const Scanning();
}

final class Pairing extends ScannerStep {
  const Pairing();
}

/// Design "Mã sai hoặc hết hạn": the sheet with the spec §5.3/§12 message.
final class PairingFailed extends ScannerStep {
  const PairingFailed(this.message);
  final String message;
}

/// Design "Ghép nối xong".
final class Paired extends ScannerStep {
  const Paired({required this.agentId, required this.machineName});
  final String agentId;
  final String machineName;
}

/// Spec §9.2 #3: one scan at a time; a failure stays on screen until "Quét lại".
@injectable
class QrScannerController extends Controller {
  QrScannerController(this._session);

  final SessionHolder _session;
  final Signal<ScannerStep> _step = signal(const Scanning());
  bool _disposed = false;

  ReadonlySignal<ScannerStep> get step => _step;

  /// Pairs with the scanned machine; codes seen while pairing or while a result is shown are
  /// ignored. Never throws: an unexpected error (a Keychain write while pinning, no backend, …)
  /// becomes [PairingFailed] with its [ErrorText], so the scanner never hangs on "Đang ghép nối…".
  ///
  /// Every `await` below can outlive the page — closing the scanner while pairing (or while the
  /// machine-name lookup that follows a success) is in flight disposes
  /// [_step] out from under this call. So [_disposed] is (re-)checked immediately after *every*
  /// await, right before the next signal write, never just once up front.
  Future<void> onCode(String raw, S strings) async {
    if (_disposed || _step.peek() is! Scanning) return;
    _step.value = const Pairing();
    final PairingOutcome outcome;
    try {
      outcome = await pairFromQrCode(raw, _session.requireBackend, ErrorText(strings));
    } catch (error) {
      if (kDebugMode) debugPrint('Pairing failed: ${error.runtimeType}');
      if (!_disposed) _step.value = PairingFailed(ErrorText(strings).describe(error));
      return;
    }
    if (_disposed) return;
    switch (outcome) {
      case PairingSucceeded(:final agentId):
        final machineName = await _nameOf(agentId, strings);
        if (_disposed) return;
        _step.value = Paired(agentId: agentId, machineName: machineName);
      case PairingRejected(:final message):
        _step.value = PairingFailed(message);
    }
  }

  Future<String> _nameOf(String agentId, S strings) async {
    try {
      for (final device in await _session.requireBackend.devices()) {
        if (device.id == agentId) return device.name;
      }
    } on Object {
      // Offline right after pairing: the list shows the name later.
    }
    return strings.unknownMachine;
  }

  void scanAgain() => _step.value = const Scanning();

  void dispose() {
    _disposed = true;
    _step.dispose();
  }
}
