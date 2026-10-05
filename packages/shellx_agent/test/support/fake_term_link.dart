import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// A [TermLink] the test drives: [emit] plays `shellx-term`, [sent] records
/// what the agent sent, [drop] is the connection dying.
final class FakeTermLink implements TermLink {
  FakeTermLink(this.info);

  @override
  final TermInfo info;
  final _messages = StreamController<TermToAgent>();
  final sent = <AgentToTerm>[];
  bool closed = false;

  @override
  Stream<TermToAgent> get messages => _messages.stream;

  @override
  void send(AgentToTerm message) {
    if (!closed) sent.add(message);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(_messages.close());
  }

  void emit(TermToAgent message) {
    if (!closed) _messages.add(message);
  }

  void snapshot(String text) => emit(
    TermSnapshot(data: Uint8List.fromList(utf8.encode(text)), last: true),
  );

  void out(String text) =>
      emit(TermOut(data: Uint8List.fromList(utf8.encode(text))));

  void drop() => close();

  /// What the phone typed, decoded.
  String get typed =>
      utf8.decode([for (final m in sent.whereType<AgentIn>()) ...m.data]);
}
