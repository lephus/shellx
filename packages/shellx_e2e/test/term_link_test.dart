@TestOn('mac-os')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart' show waitUntil;
import 'support/term_window.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

void main() {
  late TermBinaries bins;
  setUpAll(() async => bins = await buildTermBinaries());

  late Directory home;
  late DesktopSessionManager desktop;
  late TerminalSharing sharing;
  late List<AppMessage> toPhone;
  late List<TermWindow> windows;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('term-link-');
    var next = 1;
    desktop = DesktopSessionManager(nextId: () => next++);
    toPhone = [];
    desktop.outbound.listen((o) => toPhone.add(o.message));
    sharing = TerminalSharing(
      endpointPath: termEndpointPath(
        environment: {'HOME': home.path},
        windows: false,
      ),
      sessions: desktop,
    );
    windows = [];
  });

  tearDown(() async {
    for (final w in windows) {
      w.kill();
      await w.exitCode;
    }
    await sharing.stop();
    // Killing fake_window hangs up the PTY, but the shell and shellx-term
    // behind it are still winding down (they may write to HOME): retry.
    for (var attempt = 0;; attempt++) {
      try {
        await home.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 50) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  Future<TermWindow> openWindow() async {
    final w = await TermWindow.open(bins, home: home.path);
    windows.add(w);
    return w;
  }

  String phoneText(int id) => utf8.decode([
    for (final m in toPhone.whereType<OutputMessage>())
      if (m.id == id) ...m.data,
  ], allowMalformed: true);

  Future<int> sessionAppears() async {
    await waitUntil(
      () => desktop.sessions.isNotEmpty,
      timeout: const Duration(seconds: 15),
      reason: 'shellx-term never connected',
    );
    return desktop.sessions.single.id;
  }

  test('output from before the agent started, typing from the phone, the '
      'phone\'s size, the window taking the size back, exit code', () async {
    final window = await openWindow();
    window.type('echo before-agent\n');
    await window.waitFor('before-agent');

    await sharing.start();
    final id = await sessionAppears();
    desktop.attach(phone, id, 50, 20, 0);
    await waitUntil(() => phoneText(id).contains('before-agent'));
    expect(
      toPhone,
      contains(SessionDriver(id: id, by: DriverSide.phone)),
    );

    desktop.input(phone, id, Uint8List.fromList(utf8.encode('stty size\r')));
    await waitUntil(
      () => phoneText(id).contains('20 50'),
      reason: 'PTY did not take the phone size: ${phoneText(id)}',
    );

    window.type('echo from-desk\n');
    await waitUntil(
      () => toPhone.contains(SessionDriver(id: id, by: DriverSide.desktop)),
      reason: 'a window keystroke must hand the size back',
    );
    await waitUntil(() => phoneText(id).contains('from-desk'));

    desktop.input(phone, id, Uint8List.fromList(utf8.encode('exit 3\r')));
    await waitUntil(
      () => toPhone.contains(SessionExited(id: id, exitCode: 3)),
    );
    expect(await window.exitCode.timeout(const Duration(seconds: 5)), 3);
  });

  test('stopping and restarting the agent never closes the window; it '
      'comes back with its earlier output', () async {
    await sharing.start();
    final window = await openWindow();
    await sessionAppears();
    window.type('echo first-run\n');
    await window.waitFor('first-run');

    await sharing.stop();
    window.type('echo while-off\n');
    await window.waitFor('while-off');

    await sharing.start();
    final id = await sessionAppears();
    desktop.attach(phone, id, 80, 24, 0);
    await waitUntil(() => phoneText(id).contains('while-off'));
    expect(phoneText(id), contains('first-run'));

    window.type('exit\n');
    expect(await window.exitCode.timeout(const Duration(seconds: 5)), 0);
  });

  test('a phone that only leaves never ends the window', () async {
    await sharing.start();
    final window = await openWindow();
    final id = await sessionAppears();
    desktop.attach(phone, id, 80, 24, 0);
    desktop.detach(phone, id);
    desktop.disconnectAllPhones();
    window.type('echo still-here\n');
    await window.waitFor('still-here');
    expect(desktop.owns(id), isTrue);
  });
}
