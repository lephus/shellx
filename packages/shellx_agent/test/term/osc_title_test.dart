import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('OSC 0 and OSC 2, ended by BEL or ST', () {
    expect(OscTitleParser().feed(_b('\x1b]0;one\x07')), 'one');
    expect(OscTitleParser().feed(_b('\x1b]2;two\x1b\\')), 'two');
  });

  test('other OSCs and CSIs are not titles', () {
    final parser = OscTitleParser();
    expect(
      parser.feed(_b('\x1b]1;icon\x07\x1b[2J\x1b]7;file:///\x07')),
      isNull,
    );
  });

  test('the last of several titles wins', () {
    expect(OscTitleParser().feed(_b('\x1b]0;a\x07x\x1b]2;b\x07')), 'b');
  });

  test('a title split at every byte position is still found', () {
    final bytes = _b('ab\x1b]0;tiếng Việt\x07cd');
    for (var cut = 0; cut <= bytes.length; cut++) {
      final parser = OscTitleParser();
      final first = parser.feed(Uint8List.sublistView(bytes, 0, cut));
      final second = parser.feed(Uint8List.sublistView(bytes, cut));
      expect(second ?? first, 'tiếng Việt', reason: 'cut at $cut');
    }
  });

  test('titles are cut to 200 characters', () {
    final title = OscTitleParser().feed(_b('\x1b]0;${'é' * 300}\x07'));
    expect(title!.runes.length, OscTitleParser.maxTitleLength);
  });

  test('a sequence over 4 KiB is ignored, and parsing recovers', () {
    final parser = OscTitleParser();
    expect(parser.feed(_b('\x1b]0;${'x' * 5000}\x07')), isNull);
    expect(parser.feed(_b('\x1b]0;ok\x07')), 'ok');
  });

  test('reset forgets a half-read sequence', () {
    final parser = OscTitleParser()..feed(_b('\x1b]0;half'));
    parser.reset();
    expect(parser.feed(_b('\x07')), isNull);
  });
}
