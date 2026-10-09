import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'fake_term_link.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';
const tablet = 'b0000000-0000-4000-8000-000000000003';

TermInfo windowInfo(int n, {String app = 'Terminal'}) => TermInfo(
  termId: Uint8List.fromList(List.filled(16, n)),
  app: app,
  shell: 'zsh',
  pid: 1000 + n,
  cols: 80,
  rows: 24,
  startedAt: 1759276800000 + n,
);

final class DesktopRig {
  DesktopRig({int maxSessions = 32, int bufferCapacity = 256 * 1024}) {
    var next = 100;
    manager = DesktopSessionManager(
      nextId: () => next++,
      maxSessions: maxSessions,
      bufferCapacity: bufferCapacity,
    );
    manager.outbound.listen(sent.add);
  }

  late final DesktopSessionManager manager;
  final sent = <OutboundMessage>[];

  List<AppMessage> to(String mobileId) => [
    for (final o in sent)
      if (o.mobileId == mobileId) o.message,
  ];

  String text(String mobileId, int id) => utf8.decode([
    for (final m in to(mobileId).whereType<OutputMessage>())
      if (m.id == id) ...m.data,
  ]);

  /// Connects window [n] and returns its link (snapshot not yet sent).
  /// Session ids are handed out from 100 in connection order.
  FakeTermLink connect(int n, {String app = 'Terminal'}) {
    final link = FakeTermLink(windowInfo(n, app: app));
    manager.addLink(link);
    return link;
  }

  void clear() => sent.clear();
}
