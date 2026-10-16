import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

sealed class PairingOutcome {
  const PairingOutcome();
}

final class PairingSucceeded extends PairingOutcome {
  const PairingSucceeded(this.agentId);
  final String agentId;
}

final class PairingRejected extends PairingOutcome {
  const PairingRejected(this.message);
  final String message;
}

/// Spec §5.3 on the phone: parse the scanned text, run the pairing
/// handshake, and turn every failure into the spec's message.
Future<PairingOutcome> pairFromQrCode(String raw, ShellxBackend backend, ErrorText text) async {
  final PairingUri uri;
  try {
    uri = PairingUri.parse(raw.trim());
  } on FormatException {
    // Not a ShellX pairing code (or a damaged one).
    return PairingRejected(text.pairing(PairingFailure.invalidOrExpired));
  }
  try {
    await backend.pair(uri);
    return PairingSucceeded(uri.agentDeviceId);
  } on PairingException catch (error) {
    return PairingRejected(text.pairing(error.failure));
  } on ApiException catch (error) {
    return PairingRejected(text.api(error));
  }
}
