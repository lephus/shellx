import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/windows_pipe_transport.dart';
import 'package:win32/win32.dart';

// ⚠ MANUAL: every test but the first runs only on Windows (A5b Task 3
// Step 5); on macOS they are skipped.
void main() {
  test('pipe name: first 16 hex of sha256(SID), pure', () {
    expect(
      pipeNameForUser('S-1-5-21-1004336348-1177238915-682003330-1001'),
      r'\\.\pipe\shellx-mux-c683d27c80f2d3b9',
    );
    expect(pipeNameForUser('S-1-5-18'), isNot(pipeNameForUser('S-1-5-19')));
  });

  test('the client opens the pipe at identification level only (SQOS)', () {
    // A malicious server cannot impersonate the client beyond identifying
    // it; the flags are pure, so this runs everywhere.
    expect(kPipeClientFlags & FILE_FLAG_OVERLAPPED, FILE_FLAG_OVERLAPPED);
    expect(kPipeClientFlags & SECURITY_SQOS_PRESENT, SECURITY_SQOS_PRESENT);
    // SECURITY_IDENTIFICATION is level 1 in bits 16-17.
    expect(kPipeClientFlags & 0x30000, SECURITY_IDENTIFICATION);
  });

  String testPipe() =>
      '${pipeNameForUser(currentUserSid())}-test-${DateTime.now().microsecondsSinceEpoch}';

  test('listen/connect: messages flow both ways', () async {
    final t = WindowsPipeTransport();
    final listener = await t.listen(testPipe());
    final serverSide = listener.connections.first;
    final client = await t.connect(listener.address);
    final server = await serverSide;
    final got = server.messages.first;
    client.send(const MuxMessage(MuxType.daemonStatus, q: 1));
    expect((await got).q, 1);
    final back = client.messages.first;
    server.send(const MuxMessage(MuxType.result, q: 1));
    expect((await back).type, MuxType.result);
    await client.close();
    await server.done;
    await listener.close();
  }, testOn: 'windows');

  test('A7 final W1: pendingBytes counts what a peer that does not read '
      'left unwritten; its going away settles drained', () async {
    final t = WindowsPipeTransport();
    final listener = await t.listen(testPipe());
    final serverSide = listener.connections.first;
    // A raw client that never reads (as a `shellx events` stuck on its
    // stdout): the pipe's 64 KiB buffer fills, then writes wait.
    final raw = using(
      (arena) => CreateFile(
        listener.address.toNativeUtf16(allocator: arena),
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        kPipeClientFlags,
        0,
      ),
    );
    expect(raw, isNot(INVALID_HANDLE_VALUE));
    final server = await serverSide;
    for (var i = 0; i < 64; i++) {
      server.send(
        MuxMessage(MuxType.result, q: i, fields: {'pad': 'x' * 30000}),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(server.pendingBytes, greaterThan(64 * 1024));
    var drained = false;
    unawaited(server.drained.then((_) => drained = true));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(drained, isFalse);
    CloseHandle(raw);
    await server.drained.timeout(const Duration(seconds: 5));
    expect(server.pendingBytes, 0);
    await server.done.timeout(const Duration(seconds: 5));
    await listener.close();
  }, testOn: 'windows');

  test('a second listen on the same name fails (squatter, D4)', () async {
    final t = WindowsPipeTransport();
    final name = testPipe();
    final listener = await t.listen(name);
    await expectLater(t.listen(name), throwsStateError);
    await listener.close();
  }, testOn: 'windows');

  test('connect to nothing fails fast', () async {
    await expectLater(
      WindowsPipeTransport().connect(
        testPipe(),
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<Exception>()),
    );
  }, testOn: 'windows');

  test('the pipe DACL has exactly one ACE: the current user', () async {
    final t = WindowsPipeTransport();
    final listener = await t.listen(testPipe());
    // Opening the pipe by name takes one instance; drop what it accepts.
    final drained = listener.connections.listen((c) => c.close());
    expect(_aceSids(listener.address), [currentUserSid()]);
    await drained.cancel();
    await listener.close();
  }, testOn: 'windows');
}

typedef _GetNamedSecurityInfoC =
    Uint32 Function(
      Pointer<Utf16>,
      Int32,
      Uint32,
      Pointer<Pointer>,
      Pointer<Pointer>,
      Pointer<Pointer<ACL>>,
      Pointer<Pointer<ACL>>,
      Pointer<Pointer>,
    );
typedef _GetNamedSecurityInfoDart =
    int Function(
      Pointer<Utf16>,
      int,
      int,
      Pointer<Pointer>,
      Pointer<Pointer>,
      Pointer<Pointer<ACL>>,
      Pointer<Pointer<ACL>>,
      Pointer<Pointer>,
    );

/// SIDs of the ACEs in [pipe]'s DACL (`GetNamedSecurityInfoW`,
/// `SE_KERNEL_OBJECT` = 6, `GetAce`, ACE SID at offset 8).
List<String> _aceSids(String pipe) {
  final advapi = DynamicLibrary.open('advapi32.dll');
  final getInfo = advapi
      .lookupFunction<_GetNamedSecurityInfoC, _GetNamedSecurityInfoDart>(
        'GetNamedSecurityInfoW',
      );
  final getAce = advapi
      .lookupFunction<
        Int32 Function(Pointer<ACL>, Uint32, Pointer<Pointer>),
        int Function(Pointer<ACL>, int, Pointer<Pointer>)
      >('GetAce');
  return using((arena) {
    final dacl = arena<Pointer<ACL>>();
    final sd = arena<Pointer>();
    final status = getInfo(
      pipe.toNativeUtf16(allocator: arena),
      6,
      DACL_SECURITY_INFORMATION,
      nullptr,
      nullptr,
      dacl,
      nullptr,
      sd,
    );
    expect(status, 0, reason: 'GetNamedSecurityInfoW');
    try {
      final sids = <String>[];
      final ace = arena<Pointer>();
      for (var i = 0; i < dacl.value.ref.AceCount; i++) {
        expect(getAce(dacl.value, i, ace), isNot(0));
        sids.add(sidToString(Pointer<Void>.fromAddress(ace.value.address + 8)));
      }
      return sids;
    } finally {
      LocalFree(sd.value);
    }
  });
}
