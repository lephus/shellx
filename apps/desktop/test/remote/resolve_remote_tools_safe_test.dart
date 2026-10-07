import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';

void main() {
  test(
    'a resolver that throws gives empty tools, never an error (M4)',
    () async {
      final tools = await resolveRemoteToolsSafe(() => throw StateError('x'));
      expect(tools.sshPath, isNull);
      expect(tools.control, isNull);
    },
  );

  test('a resolver that hangs is cut at 2 s (M4)', () {
    fakeAsync((async) {
      RemoteTools? got;
      resolveRemoteToolsSafe(
        () => Completer<RemoteTools>().future,
      ).then((t) => got = t);
      async.elapse(const Duration(seconds: 3));
      expect(got, isNotNull);
      expect(got!.sshPath, isNull);
    });
  });

  test('a resolved value passes through', () async {
    const t = RemoteTools(sshPath: '/usr/bin/ssh');
    expect(await resolveRemoteToolsSafe(() async => t), same(t));
  });
}
