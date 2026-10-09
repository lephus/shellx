import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/process_tree.dart';

Future<bool> alive(int pid) async =>
    (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;

void main() {
  test('the whole tree stops, grandchildren too', () async {
    final dir = await Directory.systemTemp.createTemp('shellx_tree_');
    addTearDown(() => dir.delete(recursive: true));
    final pidFile = File('${dir.path}/grandchild.pid');
    final script = File('${dir.path}/run.sh')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'sh -c \'sleep 60 & echo \$! > "${pidFile.path}"; wait\' &\n'
        'wait\n',
      );
    final p = await Process.start('/bin/sh', [script.path]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    for (var i = 0; i < 100 && !pidFile.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // The pid file is written before sleep is reparented; give sh a beat.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final grandchild = int.parse(pidFile.readAsStringSync().trim());
    expect(await alive(grandchild), isTrue);
    await killProcessTree(p);
    await p.exitCode;
    var gone = false;
    for (var i = 0; i < 40 && !gone; i++) {
      gone = !await alive(grandchild);
      if (!gone) await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(gone, isTrue, reason: 'a grandchild survived the kill');
  }, skip: Platform.isWindows);

  test('a process that already ended is no error', () async {
    final p = await Process.start('/bin/sh', ['-c', 'exit 0']);
    await p.exitCode;
    await killProcessTree(p);
  }, skip: Platform.isWindows);

  test('descendantsOf follows parents, leaves last in the list', () {
    final order = descendantPids(
      10,
      '10 1\n11 10\n12 11\n13 10\n99 1\nnot a line\n',
    );
    expect(order.toSet(), {11, 12, 13});
    // Children always come after their parent: killing from the end kills
    // leaves first.
    expect(order.indexOf(11) < order.indexOf(12), isTrue);
  });
}
