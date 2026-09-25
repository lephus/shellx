import 'dart:convert';
import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'fake_pty.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';
const tablet = 'b0000000-0000-4000-8000-000000000003';

/// A [SessionManager] over [FakePtyFactory] that records every outbound
/// message.
final class SessionRig {
  SessionRig({
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Random? random,
  }) {
    manager = SessionManager(
      ptyFactory: factory,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {'PATH': '/usr/bin'},
      maxSessions: maxSessions,
      bufferCapacity: bufferCapacity,
      sendWindow: sendWindow,
      random: random ?? Random(1),
    );
    manager.outbound.listen(sent.add);
  }

  final factory = FakePtyFactory();
  late final SessionManager manager;
  final sent = <OutboundMessage>[];

  /// Messages sent to [mobileId], in order.
  List<AppMessage> to(String mobileId) => [
    for (final o in sent)
      if (o.mobileId == mobileId) o.message,
  ];

  /// Opens a session for [mobileId] and returns its id.
  Future<int> open(String mobileId, {int cols = 80, int rows = 24}) async {
    await manager.handle(mobileId, SessionOpen(cols: cols, rows: rows));
    return to(mobileId).whereType<SessionOpened>().last.id;
  }

  FakePty pty(int spawnIndex) => factory.ptys[spawnIndex];

  void clear() => sent.clear();
}

/// Concatenated output text of session [id] in [messages].
String outputText(List<AppMessage> messages, int id) => utf8.decode([
  for (final m in messages.whereType<OutputMessage>())
    if (m.id == id) ...m.data,
]);

/// Total output bytes of session [id] in [messages].
int outputBytes(List<AppMessage> messages, int id) => messages
    .whereType<OutputMessage>()
    .where((m) => m.id == id)
    .fold(0, (sum, m) => sum + m.data.length);
