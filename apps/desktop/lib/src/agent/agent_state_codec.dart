import 'dart:convert';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../terminal_sharing/config_file_editor.dart';
import '../terminal_sharing/powershell.dart';
import '../terminal_sharing/terminal_sharing_setup.dart';
import 'agent_runtime.dart';
import 'agent_state.dart';
import 'update_check.dart';

/// A5b D12: [AgentViewState] on the mux wire (`agent.get`, `agent.state`).
/// CBOR-safe values only: ints, strings, bools, lists, maps; enums by name;
/// a `DateTime` as UTC microseconds. Decoding ignores unknown keys and reads
/// a missing key as the default, so an older and a newer app still talk.
///
/// A new field of [AgentViewState] must be added here (the codec test
/// compares every field).
Map<String, Object?> agentStateToWire(AgentViewState s) => {
  'phase': s.phase.name,
  'email': ?s.email,
  'signedOutNotice': s.signedOutNotice,
  'remoteAccess': s.remoteAccess,
  'keepAwake': s.keepAwake,
  'launchAtStartup': s.launchAtStartup,
  'onboardingDone': s.onboardingDone,
  'relay': s.relay.name,
  'channels': s.activeChannels,
  'sessions': [for (final x in s.sessions) summaryToWire(x)],
  'trusted': [for (final d in s.trusted) d.toJson()],
  if (s.pairing case final p?) 'pairing': pairingToWire(p),
  if (s.update case final u?)
    'update': {
      'version': u.version,
      'url': u.url.toString(),
      'required': u.required,
    },
  'sharing': {
    'available': s.terminalSharing.available,
    'enabled': s.terminalSharing.enabled,
    'busy': s.terminalSharing.busy,
    'needsSetup': s.terminalSharing.needsSetup,
    'sessions': [
      for (final d in s.terminalSharing.sessions) _desktopSessionToWire(d),
    ],
  },
  'notifyThreshold': s.notifyThresholdSeconds,
  'desktopNotifications': s.desktopNotifications,
  'desktopNotificationsOnlyUnfocused': s.desktopNotificationsOnlyUnfocused,
  'cliControl': s.cliControlEnabled,
  'cliAllowExternal': s.cliAllowExternal,
  'sshRemoteHook': s.sshRemoteHook,
};

/// Throws [FormatException] or [TypeError] for a value of the wrong shape;
/// the caller keeps the state it had.
AgentViewState agentStateFromWire(Map<Object?, Object?> m) {
  const d = AgentViewState();
  final sharing = m['sharing'] as Map<Object?, Object?>?;
  final update = m['update'] as Map<Object?, Object?>?;
  final pairing = m['pairing'] as Map<Object?, Object?>?;
  return AgentViewState(
    phase: _enum(AuthPhase.values, m['phase'], d.phase),
    email: m['email'] as String?,
    signedOutNotice: m['signedOutNotice'] as bool? ?? d.signedOutNotice,
    remoteAccess: m['remoteAccess'] as bool? ?? d.remoteAccess,
    keepAwake: m['keepAwake'] as bool? ?? d.keepAwake,
    launchAtStartup: m['launchAtStartup'] as bool? ?? d.launchAtStartup,
    onboardingDone: m['onboardingDone'] as bool? ?? d.onboardingDone,
    relay: _enum(RelayConnectionState.values, m['relay'], d.relay),
    activeChannels: m['channels'] as int? ?? d.activeChannels,
    sessions: _entries(m['sessions'], (x) => summaryFromWire(x)),
    trusted: _entries(
      m['trusted'],
      (x) => TrustedDevice.fromJson({
        for (final e in x.entries) e.key! as String: e.value,
      }),
    ),
    pairing: pairing == null ? null : pairingFromWire(pairing),
    update: update == null
        ? null
        : UpdateNotice(
            version: update['version']! as String,
            url: Uri.parse(update['url']! as String),
            required: update['required'] as bool? ?? false,
          ),
    terminalSharing: sharing == null
        ? d.terminalSharing
        : TerminalSharingView(
            available: sharing['available'] as bool? ?? false,
            enabled: sharing['enabled'] as bool? ?? false,
            busy: sharing['busy'] as bool? ?? false,
            needsSetup: sharing['needsSetup'] as bool? ?? false,
            sessions: _entries(sharing['sessions'], _desktopSessionFromWire),
          ),
    notifyThresholdSeconds:
        m['notifyThreshold'] as int? ?? d.notifyThresholdSeconds,
    desktopNotifications:
        m['desktopNotifications'] as bool? ?? d.desktopNotifications,
    desktopNotificationsOnlyUnfocused:
        m['desktopNotificationsOnlyUnfocused'] as bool? ??
        d.desktopNotificationsOnlyUnfocused,
    cliControlEnabled: m['cliControl'] as bool? ?? d.cliControlEnabled,
    cliAllowExternal: m['cliAllowExternal'] as bool? ?? d.cliAllowExternal,
    sshRemoteHook: m['sshRemoteHook'] as bool? ?? d.sshRemoteHook,
  );
}

/// The entries that decode; one bad entry (a newer app's shape) is skipped,
/// not the whole state.
List<T> _entries<T>(Object? v, T Function(Map<Object?, Object?>) decode) => [
  for (final x in _list(v))
    if (x is Map<Object?, Object?>) ?_tryDecode(x, decode),
];

T? _tryDecode<T>(Map<Object?, Object?> x, T Function(Map<Object?, Object?>) f) {
  try {
    return f(x);
  } on Object {
    return null;
  }
}

List<Object?> _list(Object? v) => v as List<Object?>? ?? const [];

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback; // a newer app's value: never fail the whole state
}

Map<String, Object?> pairingToWire(PairingView p) => {
  'uri': p.uri.toUriString(),
  'expires': p.expiresAt.toUtc().microsecondsSinceEpoch,
};

PairingView pairingFromWire(Map<Object?, Object?> m) => PairingView(
  uri: PairingUri.parse(m['uri']! as String),
  expiresAt: DateTime.fromMicrosecondsSinceEpoch(
    m['expires']! as int,
    isUtc: true,
  ),
);

Map<String, Object?> _desktopSessionToWire(DesktopSessionSummary s) => {
  'id': s.id,
  'index': s.index,
  'app': s.app,
  'title': s.title,
  'shell': s.shell,
  'created': s.createdAt.toUtc().microsecondsSinceEpoch,
  'mobile': s.attachedMobileId,
  'connected': s.connected,
};

DesktopSessionSummary _desktopSessionFromWire(Map<Object?, Object?> m) =>
    DesktopSessionSummary(
      id: m['id']! as int,
      index: m['index']! as int,
      app: m['app']! as String,
      title: m['title']! as String,
      shell: m['shell']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        m['created']! as int,
        isUtc: true,
      ),
      attachedMobileId: m['mobile'] as String?,
      connected: m['connected'] as bool? ?? true,
    );

/// The confirmation's content travels to the UI and back with
/// `enableTerminalSharing`.
Map<String, Object?> sharingPlanToWire(SharingPlan p) => {
  'files': [
    for (final f in p.files)
      {
        'path': f.target.path,
        'block': f.target.block,
        'create': f.target.create,
        'eol': f.target.newFileEol,
        'exists': f.exists,
      },
  ],
  'bashSkipped': p.bashSkipped,
  'powerShells': [
    for (final s in p.powerShells)
      {
        'name': s.name,
        'executable': s.executable,
        'profile': s.profilePath,
        'policy': s.policy.name,
      },
  ],
};

SharingPlan sharingPlanFromWire(Map<Object?, Object?> m) {
  PlannedFile file(Object? raw) {
    final x = raw! as Map<Object?, Object?>;
    return PlannedFile(
      ConfigTarget(
        path: x['path']! as String,
        block: x['block']! as String,
        create: x['create']! as bool,
        newFileEol: x['eol']! as String,
      ),
      exists: x['exists']! as bool,
    );
  }

  PowerShellInstall shell(Object? raw) {
    final x = raw! as Map<Object?, Object?>;
    return PowerShellInstall(
      name: x['name']! as String,
      executable: x['executable']! as String,
      profilePath: x['profile']! as String,
      policy: _enum(ScriptPolicy.values, x['policy'], ScriptPolicy.blocked),
    );
  }

  return SharingPlan(
    files: [for (final x in _list(m['files'])) file(x)],
    bashSkipped: m['bashSkipped'] as bool? ?? false,
    powerShells: [for (final x in _list(m['powerShells'])) shell(x)],
  );
}

/// What the UI shows for the confirmation and sends back to enable: the
/// daemon compares it with its own `prepare()` and enables only its own
/// plan (a plan carries paths and shell blocks, never taken from a peer).
String sharingPlanDigest(SharingPlan p) => jsonEncode(sharingPlanToWire(p));
