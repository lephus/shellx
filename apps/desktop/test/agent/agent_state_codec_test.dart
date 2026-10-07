import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/agent_state_codec.dart';
import 'package:shellx_desktop/src/agent/update_check.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';
import 'package:shellx_desktop/src/terminal_sharing/powershell.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';

import '../support/fakes.dart';

void expectSameMoment(DateTime a, DateTime b) =>
    expect(a.isAtSameMomentAs(b), isTrue, reason: '$a vs $b');

void expectSameSession(SessionSummary a, SessionSummary b) {
  expect(b.id, a.id);
  expect(b.index, a.index);
  expect(b.shell, a.shell);
  expectSameMoment(b.createdAt, a.createdAt);
  expect(b.attachedMobileId, a.attachedMobileId);
  expect(b.origin, a.origin);
  expect(b.title, a.title);
  expect(b.driver, a.driver);
  expect(b.runningCommand, a.runningCommand);
  expect(b.cwd, a.cwd);
  expect(b.gitBranch, a.gitBranch);
  expect(b.ports, a.ports);
  expect(b.remote == null, a.remote == null);
  if (a.remote case final r?) {
    expect(b.remote!.connected, r.connected);
    expect(b.remote!.home, r.home);
    expect(b.remote!.launch.toJson(), r.launch.toJson());
  }
}

/// Every field of [AgentViewState], nested lists included.
void expectSameState(AgentViewState a, AgentViewState b) {
  expect(b.phase, a.phase);
  expect(b.email, a.email);
  expect(b.signedOutNotice, a.signedOutNotice);
  expect(b.remoteAccess, a.remoteAccess);
  expect(b.keepAwake, a.keepAwake);
  expect(b.launchAtStartup, a.launchAtStartup);
  expect(b.onboardingDone, a.onboardingDone);
  expect(b.relay, a.relay);
  expect(b.activeChannels, a.activeChannels);
  expect(b.sessions, hasLength(a.sessions.length));
  for (var i = 0; i < a.sessions.length; i++) {
    expectSameSession(a.sessions[i], b.sessions[i]);
  }
  expect(b.trusted, hasLength(a.trusted.length));
  for (var i = 0; i < a.trusted.length; i++) {
    final x = a.trusted[i], y = b.trusted[i];
    expect(y.mobileId, x.mobileId);
    expect(y.publicKey, x.publicKey);
    expect(y.name, x.name);
    expect(
      y.pairedAt.millisecondsSinceEpoch,
      x.pairedAt.millisecondsSinceEpoch,
    );
    expect(y.pairingId, x.pairingId);
  }
  expect(b.pairing == null, a.pairing == null);
  if (a.pairing case final p?) {
    expect(b.pairing!.uri.toUriString(), p.uri.toUriString());
    expectSameMoment(b.pairing!.expiresAt, p.expiresAt);
  }
  expect(b.update == null, a.update == null);
  if (a.update case final u?) {
    expect(b.update!.version, u.version);
    expect(b.update!.url, u.url);
    expect(b.update!.required, u.required);
  }
  final x = a.terminalSharing, y = b.terminalSharing;
  expect(y.available, x.available);
  expect(y.enabled, x.enabled);
  expect(y.busy, x.busy);
  expect(y.needsSetup, x.needsSetup);
  expect(y.sessions, hasLength(x.sessions.length));
  for (var i = 0; i < x.sessions.length; i++) {
    final p = x.sessions[i], q = y.sessions[i];
    expect(q.id, p.id);
    expect(q.index, p.index);
    expect(q.app, p.app);
    expect(q.title, p.title);
    expect(q.shell, p.shell);
    expectSameMoment(q.createdAt, p.createdAt);
    expect(q.attachedMobileId, p.attachedMobileId);
    expect(q.connected, p.connected);
  }
  expect(b.notifyThresholdSeconds, a.notifyThresholdSeconds);
  expect(b.desktopNotifications, a.desktopNotifications);
  expect(
    b.desktopNotificationsOnlyUnfocused,
    a.desktopNotificationsOnlyUnfocused,
  );
  expect(b.cliControlEnabled, a.cliControlEnabled);
  expect(b.cliAllowExternal, a.cliAllowExternal);
  expect(b.sshRemoteHook, a.sshRemoteHook);
}

AgentViewState fullState() => AgentViewState(
  phase: AuthPhase.signedIn,
  email: 'phu@example.com',
  signedOutNotice: true,
  remoteAccess: false,
  keepAwake: false,
  launchAtStartup: false,
  onboardingDone: true,
  relay: RelayConnectionState.values.last,
  activeChannels: 3,
  sessions: [
    SessionSummary(
      id: 1,
      index: 1,
      shell: 'zsh',
      createdAt: DateTime.utc(2026, 10, 6, 8, 30, 1, 250, 5),
      attachedMobileId: 'm1',
      origin: SessionOrigin.phone,
      title: 'vim',
      driver: DriverSide.phone,
      runningCommand: true,
      cwd: '/work',
      gitBranch: 'main',
      ports: const [3000, 8080],
    ),
    SessionSummary(
      id: 2,
      index: 2,
      shell: 'bash',
      createdAt: DateTime.utc(2026, 10, 6, 9),
      attachedMobileId: null,
      origin: SessionOrigin.desktop,
      title: '',
      driver: DriverSide.desktop,
    ),
  ],
  trusted: [phone('m1', 'iPhone của Phú'), phone('m2', 'Pixel')],
  pairing: PairingView(
    uri: PairingUri(
      agentDeviceId: '0198b1d2-7c3a-7b1e-8a55-1f2e3d4c5b6a',
      agentPublicKey: Uint8List.fromList(List.generate(32, (i) => i)),
      secret: Uint8List.fromList(List.generate(32, (i) => 255 - i)),
    ),
    expiresAt: DateTime.utc(2026, 10, 7, 12, 5),
  ),
  update: UpdateNotice(
    version: '1.4.0',
    url: Uri.parse('https://shellx.pro/download/1.4.0'),
    required: true,
  ),
  terminalSharing: TerminalSharingView(
    available: true,
    enabled: true,
    busy: true,
    needsSetup: true,
    sessions: [
      DesktopSessionSummary(
        id: 7,
        index: 1,
        app: 'iTerm',
        title: 'build',
        shell: 'zsh',
        createdAt: DateTime.utc(2026, 10, 7, 1),
        attachedMobileId: 'm2',
        connected: false,
      ),
    ],
  ),
  notifyThresholdSeconds: 30,
  desktopNotifications: false,
  desktopNotificationsOnlyUnfocused: false,
  cliControlEnabled: false,
  cliAllowExternal: true,
  sshRemoteHook: false,
);

void main() {
  test('a fully populated state survives the wire, field by field', () {
    final s = fullState();
    expectSameState(s, agentStateFromWire(agentStateToWire(s)));
  });

  test('the defaults survive too (nulls stay null, lists stay empty)', () {
    const s = AgentViewState();
    expectSameState(s, agentStateFromWire(agentStateToWire(s)));
  });

  test('it is CBOR-safe: the bytes of a state decode to the same state', () {
    final s = fullState();
    final bytes = encodeMux(
      MuxMessage(MuxType.agentState, fields: {'state': agentStateToWire(s)}),
    );
    final back = MuxFrameDecoder().add(bytes).single;
    final wire = back.get<Map<Object?, Object?>>('state')!;
    expectSameState(s, agentStateFromWire(wire));
  });

  test('every enum survives', () {
    for (final phase in AuthPhase.values) {
      for (final relay in RelayConnectionState.values) {
        final s = AgentViewState(phase: phase, relay: relay);
        final b = agentStateFromWire(agentStateToWire(s));
        expect((b.phase, b.relay), (phase, relay));
      }
    }
  });

  test('unknown keys are ignored and missing keys read as the defaults', () {
    final full = fullState();
    final wire = <Object?, Object?>{...agentStateToWire(full)};
    wire['from_the_future'] = {'x': 1};
    final partial = agentStateFromWire({'phase': 'signedIn'});
    expect(partial.signedIn, isTrue);
    expect(partial.cliControlEnabled, isTrue);
    expect(partial.cliAllowExternal, isFalse);
    expect(partial.sshRemoteHook, isTrue);
    expectSameState(full, agentStateFromWire(wire));
  });

  test('a sharing plan survives the wire', () {
    final plan = SharingPlan(
      files: const [
        PlannedFile(
          ConfigTarget(
            path: '/Users/phu/.zshrc',
            block: '# block\n',
            create: true,
            newFileEol: '\n',
          ),
          exists: false,
        ),
        PlannedFile(
          ConfigTarget(
            path: '/Users/phu/.bash_profile',
            block: '# b\n',
            create: false,
            newFileEol: '\r\n',
          ),
          exists: true,
        ),
      ],
      bashSkipped: true,
      powerShells: const [
        PowerShellInstall(
          name: 'PowerShell 7',
          executable: 'pwsh',
          profilePath: r'C:\p\profile.ps1',
          policy: ScriptPolicy.blockedByGroupPolicy,
        ),
      ],
    );
    final back = sharingPlanFromWire(sharingPlanToWire(plan));
    expect(back.bashSkipped, isTrue);
    expect(back.files, hasLength(2));
    for (var i = 0; i < 2; i++) {
      final a = plan.files[i], b = back.files[i];
      expect(b.exists, a.exists);
      expect(b.target.path, a.target.path);
      expect(b.target.block, a.target.block);
      expect(b.target.create, a.target.create);
      expect(b.target.newFileEol, a.target.newFileEol);
    }
    final p = back.powerShells.single;
    expect(p.name, 'PowerShell 7');
    expect(p.executable, 'pwsh');
    expect(p.profilePath, r'C:\p\profile.ps1');
    expect(p.policy, ScriptPolicy.blockedByGroupPolicy);
  });

  test('unknown enum names fall back to the defaults', () {
    final b = agentStateFromWire({'phase': 'from_the_future', 'relay': 'x'});
    expect(b.phase, const AgentViewState().phase);
    expect(b.relay, const AgentViewState().relay);
    final plan = sharingPlanFromWire({
      'files': const [],
      'powerShells': [
        {'name': 'p', 'executable': 'e', 'profile': 'f', 'policy': 'nope'},
      ],
    });
    expect(plan.powerShells.single.policy, ScriptPolicy.blocked);
  });

  test('a bad session or trusted entry is skipped, not the whole state', () {
    final good = agentStateToWire(fullState());
    final wire = <Object?, Object?>{
      ...good,
      'sessions': [
        {'id': 'bad'},
        ...(good['sessions']! as List<Object?>),
      ],
      'trusted': [
        {'mobile_id': 1},
        ...(good['trusted']! as List<Object?>),
      ],
    };
    final b = agentStateFromWire(wire);
    expect(b.sessions, hasLength(2));
    expect(b.trusted, hasLength(2));
    expect(b.email, 'phu@example.com');
  });
}
