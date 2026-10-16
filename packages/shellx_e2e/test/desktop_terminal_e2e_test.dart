@TestOn('mac-os')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';
import 'support/term_window.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

Uint8List keys(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late TermBinaries bins;
  setUpAll(() async {
    if (relayUrl != null) bins = await buildTermBinaries();
  });

  group(
    'desktop terminal end-to-end over a real relay (spec §11.4)',
    () {
      test('list → attach → earlier output → type → detach → re-attach → '
          'window exits', () async {
        final world = await E2eWorld.create(Uri.parse(relayUrl!));
        addTearDown(world.dispose);
        await world.pair(world.phone, registered: false);
        await world.sharing.start();

        final window = await TermWindow.open(bins, home: world.home.path);
        addTearDown(window.kill);
        window.type('echo before-phone\n');
        await window.waitFor('before-phone');
        await waitUntil(
          () => world.desktop.sessions.isNotEmpty,
          reason: 'shellx-term never reached the agent',
        );

        final machine = world.phone.service.machine(world.agentId);
        await machine.connect();
        final listed = await machine.listSessions(includeDesktop: true);
        expect(machine.desktopSharing, isTrue);
        final info = listed.singleWhere((s) => s.kind == SessionKind.desktop);

        var tab = await machine.attach(info.id, cols: 60, rows: 20);
        var output = TabText(tab);
        await waitUntil(
          () => output.text.contains('before-phone'),
          reason: 'no earlier output: ${jsonEncode(output.text)}',
        );
        machine.input(tab.id, keys('echo from-phone\r'));
        await window.waitFor('from-phone');

        await machine.closeTab(tab.id);
        await waitUntil(
          () => world.desktop.sessions.single.attachedMobileId == null,
        );
        window.type('echo while-detached\n');
        await window.waitFor('while-detached');

        tab = await machine.attach(info.id, cols: 60, rows: 20);
        output = TabText(tab);
        await waitUntil(() => output.text.contains('while-detached'));

        final ended = tab.events.firstWhere((e) => e is TabExited);
        window.type('exit 4\n');
        expect(((await ended) as TabExited).exitCode, 4);
        expect(await window.exitCode, 4);
      });
    },
    skip: relayUrl == null
        ? 'Set SHELLX_E2E_RELAY=http://127.0.0.1:8787 (npm run dev in relay/) '
              'to run'
        : null,
  );
}
