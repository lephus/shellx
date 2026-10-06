import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late WorkspaceRegistry registry;
  late TerminalPageController controller;

  setUp(() async {
    getIt.registerSingleton<PopupHandler>(FakePopupHandler());
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    controller = TerminalPageController(agentA, registry, session, AppSettings(InMemoryKeyValueStore()));
    await controller.prepare();
    await controller.openNew(fallbackGrid);
  });

  tearDown(() async {
    controller.dispose();
    registry.dispose();
    await getIt.reset();
  });

  List<String> inputs() => [for (final input in machine.inputs) utf8.decode(input.data)];

  test('plain mode: the text, then Enter', () {
    controller.submitLine('git status');
    expect(inputs().join(), 'git status\r');
  });

  test('bracketed paste: Enter goes after the closing bracket', () {
    machine.handles.single.emit(const TabOutput('\x1b[?2004h'));
    controller.submitLine('sửa bug trong auth');
    expect(inputs().join(), '\x1b[200~sửa bug trong auth\x1b[201~\r');
  });

  test('an empty line is just Enter', () {
    controller.submitLine('');
    expect(inputs().join(), '\r');
  });

  test('plain mode joins line breaks with spaces so nothing runs early (review focus 1)', () {
    controller.submitLine('echo 1\necho 2\r\necho 3');
    expect(inputs().join(), 'echo 1 echo 2 echo 3\r');
  });

  test('bracketed paste keeps line breaks (as CR, like Paste)', () {
    machine.handles.single.emit(const TabOutput('\x1b[?2004h'));
    controller.submitLine('a\nb');
    expect(inputs().join(), '\x1b[200~a\rb\x1b[201~\r');
  });

  test('a sticky Ctrl is not applied to the line (review focus 2)', () {
    registry.forMachine(agentA).extraKeys.tapModifier(ExtraKey.ctrl);
    controller.submitLine('ls');
    expect(inputs().join(), 'ls\r');
  });
}
