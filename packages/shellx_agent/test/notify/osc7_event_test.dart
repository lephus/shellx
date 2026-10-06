import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('OSC 7 is reported with BEL or ST, across chunks (A2 C1)', () {
    final parser = OscEventParser();
    expect(parser.feed(_b('\x1b]7;file://mbp/Users/r/a%20b\x07')), [
      const CwdReported('file://mbp/Users/r/a%20b'),
    ]);
    expect(parser.feed(_b('ls\r\n\x1b]7;file:///t')), isEmpty);
    expect(parser.feed(_b('mp\x1b\\')), [const CwdReported('file:///tmp')]);
  });

  test('a non-file URL and an oversized payload are ignored', () {
    final parser = OscEventParser();
    expect(parser.feed(_b('\x1b]7;http://x/y\x07')), isEmpty);
    expect(parser.feed(_b('\x1b]7;file:///${'a' * 5000}\x07')), isEmpty);
    // The parser is back in its ground state afterwards.
    expect(parser.feed(_b('\x1b]133;C\x07')), [const CommandStarted()]);
  });

  test('CommandTracker ignores CwdReported', () {
    final tracker = CommandTracker(threshold: () => Duration.zero);
    expect(tracker.handle(const CwdReported('file:///tmp')), isNull);
    expect(tracker.running, isFalse);
  });
}
