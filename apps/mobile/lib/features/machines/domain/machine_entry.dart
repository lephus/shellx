import 'package:equatable/equatable.dart';
import 'package:shellx_core/shellx_core.dart';

/// One computer (agent) of the account as shown on the machine list.
final class MachineEntry extends Equatable {
  const MachineEntry({
    required this.id,
    required this.name,
    required this.platform,
    required this.online,
    required this.lastSeenAt,
    required this.paired,
  });

  final String id;
  final String name;
  final DevicePlatform platform;
  final bool online;
  final DateTime? lastSeenAt;

  /// Pinned on this phone for the signed-in user. The server's
  /// `paired_with_me` is display-only; the pin decides (spec §5.4).
  final bool paired;

  MachineEntry copyWith({bool? online, DateTime? lastSeenAt}) => MachineEntry(
    id: id,
    name: name,
    platform: platform,
    online: online ?? this.online,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    paired: paired,
  );

  @override
  List<Object?> get props => [id, name, platform, online, lastSeenAt, paired];
}

/// The machine list as one value for a `StateSignal`.
final class MachineList extends Equatable {
  const MachineList(this.machines);

  final List<MachineEntry> machines;

  @override
  List<Object?> get props => [machines];
}
