import 'package:shellx_core/shellx_core.dart';

/// Why [ClientService.pair] failed (spec §5.3, §12).
enum PairingFailure {
  /// The QR's agent id is not a device of this account.
  notInAccount,

  /// Wrong, expired or already used pairing code.
  invalidOrExpired,
  agentOffline,
  protocolUnsupported,
  timeout,
}

final class PairingException implements Exception {
  const PairingException(this.failure);
  final PairingFailure failure;
  @override
  String toString() => 'PairingException(${failure.name})';
}

/// Why an IK handshake with a pinned machine failed.
enum MachineConnectionFailure {
  untrusted,
  protocolUnsupported,
  agentOffline,
  timeout,
}

/// Thrown by [MachineClient] operations when the machine cannot be reached.
final class MachineConnectionException implements Exception {
  const MachineConnectionException(this.failure);
  final MachineConnectionFailure failure;
  @override
  String toString() => 'MachineConnectionException(${failure.name})';
}

sealed class MachineConnectionState {
  const MachineConnectionState();
}

final class MachineIdle extends MachineConnectionState {
  const MachineIdle();
}

final class MachineConnecting extends MachineConnectionState {
  const MachineConnecting();
}

final class MachineReady extends MachineConnectionState {
  const MachineReady();
}

final class MachineFailed extends MachineConnectionState {
  const MachineFailed(this.failure);
  final MachineConnectionFailure failure;
}

/// An `error` message from the agent answering one of our requests.
final class AppErrorException implements Exception {
  const AppErrorException(this.code, this.message);
  final AppErrorCode code;
  final String message;
  @override
  String toString() => 'AppErrorException(${code.wire}: $message)';
}
