import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_pty.dart';

/// The run sheet's PTYs, with what each was started with.
final class SheetPtys implements PtyFactory {
  final spawned =
      <
        ({
          ShellCommand command,
          String cwd,
          Map<String, String> env,
          FakePty pty,
        })
      >[];

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final pty = FakePty(initialCols: cols, initialRows: rows);
    spawned.add((
      command: command,
      cwd: workingDirectory,
      env: environment,
      pty: pty,
    ));
    return pty;
  }
}

/// V2-1 D8: sign-ins and installs in the run sheet.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<ProviderContainer> workspace(
    WidgetTester t,
    FakeAiRuntimes fakes,
    SheetPtys ptys, {
    List<String>? made,
  }) async {
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiPtyFactoryProvider.overrideWithValue(ptys),
        aiMakeFolderProvider.overrideWithValue((path) async => made?.add(path)),
      ],
    );
    openTestAiTab(w.container, cwd: testAiCwd);
    await t.pumpAndSettle();
    return w.container;
  }

  testWidgets('a terminal sign-in runs the agent\'s own command with the '
      'method\'s args and env in a real terminal; exit 0 opens the session', (
    t,
  ) async {
    final auth = Directory.systemTemp.createTempSync('ai_auth');
    addTearDown(() => auth.deleteSync(recursive: true));
    final fakes = FakeAiRuntimes(
      FakeScenario(
        requireAuth: true,
        authFile: '${auth.path}/signed-in',
        authMethods: const [
          {
            'id': 'claude-login',
            'name': 'Log in with Claude',
            'type': 'terminal',
            'args': ['/login'],
            'env': {'CLAUDE_LOGIN': '1'},
          },
        ],
      ),
    );
    final ptys = SheetPtys();
    final c = await workspace(t, fakes, ptys);
    expect(find.text('Claude needs you to sign in'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ai.login.claude-login')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsOneWidget);
    expect(find.text('Sign in to Claude'), findsOneWidget);
    final run = ptys.spawned.single;
    expect(run.command.executable, 'fake-agent');
    expect(run.command.arguments, ['/login']);
    expect(run.cwd, testAiCwd);
    expect(run.env['CLAUDE_LOGIN'], '1');
    expect(run.env['TERM'], 'xterm-256color');
    expect(run.env['COLORTERM'], 'truecolor');
    // The user signs in there; ShellX reads none of it.
    run.pty.emit('Opening your browser…\r\n');
    File('${auth.path}/signed-in').writeAsStringSync('ok');
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(fakes.made.single.state.phase, AgentPhase.ready);
    expect(
      fakes.agent().received.where((r) => r == 'session/new'),
      hasLength(2),
    );
    expect(fakes.agent().received, isNot(contains(startsWith('authenticate'))));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a failed sign-in keeps the sheet with its exit code; Try '
      'again runs it again; Close stops what still runs', (t) async {
    final fakes = FakeAiRuntimes(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
        ],
      ),
    );
    final ptys = SheetPtys();
    final c = await workspace(t, fakes, ptys);
    await t.tap(find.byKey(const ValueKey('ai.login.login')));
    await t.pumpAndSettle();
    ptys.spawned.single.pty.exit(1);
    await t.pumpAndSettle();
    expect(
      find.text('Sign-in did not work. Ended with exit code 1'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ai.runSheet.retry')));
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(2));
    expect(find.byKey(const Key('ai.runSheet.failed')), findsNothing);
    await t.tap(find.byKey(const Key('ai.runSheet.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(ptys.spawned.last.pty.killed, isTrue);
    expect(ptys.spawned.first.pty.killed, isFalse, reason: 'it had ended');
    expect(fakes.made.single.state.phase, AgentPhase.needsAuth);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Install runs the pinned install in its folder, made first, '
      'with a real terminal; then the agent starts (D6, D7)', (t) async {
    const install = AgentCommand(
      executable: '/usr/local/bin/node',
      args: ['/usr/local/lib/node_modules/npm/bin/npm-cli.js', 'install'],
      environment: {'PATH': '/usr/local/bin:/usr/bin', 'TERM': 'dumb'},
      workingDirectory: '/support/ai/agents/claude',
    );
    final fakes = FakeAiRuntimes(
      const FakeScenario(),
      readiness: const AgentNeedsInstall(install),
    );
    final ptys = SheetPtys();
    final made = <String>[];
    final c = await workspace(t, fakes, ptys, made: made);
    expect(find.text('Claude is not installed'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.install')));
    await t.pumpAndSettle();
    expect(made, ['/support/ai/agents/claude']);
    final run = ptys.spawned.single;
    expect(run.command.executable, '/usr/local/bin/node');
    expect(run.command.arguments, install.args);
    expect(run.cwd, '/support/ai/agents/claude');
    expect(run.env['PATH'], '/usr/local/bin:/usr/bin');
    expect(run.env['TERM'], 'xterm-256color', reason: 'not the agents\' dumb');
    expect(find.text('Install Claude'), findsOneWidget);
    fakes.readiness = null;
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(fakes.launcher.channels, hasLength(1));
    expect(fakes.made.single.state.phase, AgentPhase.ready);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
