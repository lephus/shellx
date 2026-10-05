import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

List<OscEvent> _parse(String s) => OscEventParser().feed(_b(s));

const esc = '\x1b';
const bel = '\x07';
const st = '$esc\\';

void main() {
  group('OSC 133 / 633', () {
    test('133;C starts, 133;D;<code> ends, with BEL or ST', () {
      expect(_parse('$esc]133;C$bel'), [const CommandStarted()]);
      expect(_parse('$esc]133;C$st'), [const CommandStarted()]);
      expect(_parse('$esc]133;D;1$bel'), [const CommandFinished(1)]);
      expect(_parse('$esc]133;D;130$st'), [const CommandFinished(130)]);
    });

    test(
      '133;D without a code (or an empty one) is 0; extra fields ignored',
      () {
        expect(_parse('$esc]133;D$bel'), [const CommandFinished(0)]);
        expect(_parse('$esc]133;D;$bel'), [const CommandFinished(0)]);
        expect(_parse('$esc]133;D;2;aid=7$bel'), [const CommandFinished(2)]);
        expect(_parse('$esc]133;C;cmdline=x$bel'), [const CommandStarted()]);
      },
    );

    test('133;A/B, a non-numeric D code and other 633 kinds are ignored', () {
      expect(_parse('$esc]133;A$bel$esc]133;B$bel'), isEmpty);
      expect(_parse('$esc]133;D;x$bel'), isEmpty);
      expect(_parse('$esc]633;A$bel$esc]633;C$bel$esc]633;D;1$bel'), isEmpty);
      expect(_parse('$esc]633;P;Cwd=/tmp$bel'), isEmpty);
    });

    test('633;E carries the command line, VS Code escaping undone', () {
      expect(_parse('$esc]633;E;make test$bel'), [
        const CommandLineSeen('make test'),
      ]);
      expect(_parse('$esc]633;E;sleep 1\\x3b false;nonce123$bel'), [
        const CommandLineSeen('sleep 1; false'),
      ]);
      expect(_parse('$esc]633;E;echo a\\\\b\\x0aecho c$bel'), [
        const CommandLineSeen('echo a\\b\necho c'),
      ]);
      expect(_parse('$esc]633;E;odd \\q \\x\\xZZ$bel'), [
        const CommandLineSeen('odd \\q \\x\\xZZ'),
      ]);
      expect(_parse('$esc]633;E;$bel'), [const CommandLineSeen('')]);
      expect(_parse('$esc]633;E$bel'), isEmpty);
    });
  });

  group('OSC 9 / 777', () {
    test('OSC 9 is a notification without a title', () {
      expect(_parse('$esc]9;Build xong$bel'), [
        const NotifyRequested(title: null, body: 'Build xong'),
      ]);
      expect(_parse('$esc]9;a;b$st'), [
        const NotifyRequested(title: null, body: 'a;b'),
      ]);
    });

    test('OSC 9;<digits>; (ConEmu / Windows Terminal progress) is ignored', () {
      expect(_parse('$esc]9;4;1;50$bel'), isEmpty);
      expect(_parse('$esc]9;4;0$bel'), isEmpty);
      expect(_parse('$esc]9;12;x$bel'), isEmpty);
      expect(_parse('$esc]9;$bel'), isEmpty);
      expect(_parse('$esc]9;42$bel'), [
        const NotifyRequested(title: null, body: '42'),
      ]);
    });

    test('OSC 777;notify;<title>;<body>; an empty title is null', () {
      expect(_parse('$esc]777;notify;Tiêu đề;Nội dung$bel'), [
        const NotifyRequested(title: 'Tiêu đề', body: 'Nội dung'),
      ]);
      expect(_parse('$esc]777;notify;;x;y$bel'), [
        const NotifyRequested(title: null, body: 'x;y'),
      ]);
      expect(_parse('$esc]777;notify;only-body$bel'), [
        const NotifyRequested(title: null, body: 'only-body'),
      ]);
    });

    test('other 777 commands and an empty body are ignored', () {
      expect(_parse('$esc]777;preexec$bel'), isEmpty);
      expect(_parse('$esc]777;notify;t;$bel'), isEmpty);
      expect(_parse('$esc]777;notifyx;t;b$bel'), isEmpty);
    });

    test('titles and bodies are cut to 200 characters', () {
      final long = 'é' * 300;
      final event =
          _parse('$esc]777;notify;$long;$long$bel').single as NotifyRequested;
      expect(event.title!.runes.length, 200);
      expect(event.body.runes.length, 200);
      final line = _parse('$esc]633;E;$long$bel').single as CommandLineSeen;
      expect(line.commandLine.runes.length, 200);
    });
  });

  group('robustness', () {
    const all =
        'a$esc]633;E;make$bel b $esc]133;C$st c$esc]133;D;2$bel '
        '$esc]9;hi$bel $esc]777;notify;T;B$st d';
    const expected = [
      CommandLineSeen('make'),
      CommandStarted(),
      CommandFinished(2),
      NotifyRequested(title: null, body: 'hi'),
      NotifyRequested(title: 'T', body: 'B'),
    ];

    test('several sequences in one chunk, text in between', () {
      expect(_parse(all), expected);
    });

    test('split at every byte boundary gives the same events', () {
      final bytes = _b(all);
      for (var cut = 0; cut <= bytes.length; cut++) {
        final parser = OscEventParser();
        final events = [
          ...parser.feed(Uint8List.sublistView(bytes, 0, cut)),
          ...parser.feed(Uint8List.sublistView(bytes, cut)),
        ];
        expect(events, expected, reason: 'cut at $cut');
      }
    });

    test('byte by byte', () {
      final parser = OscEventParser();
      final events = [
        for (final b in _b(all)) ...parser.feed(Uint8List.fromList([b])),
      ];
      expect(events, expected);
    });

    test('a payload over 4 KiB is skipped, and parsing resumes after it', () {
      final big = 'x' * 5000;
      expect(_parse('$esc]9;$big$bel$esc]133;C$bel'), [const CommandStarted()]);
      final exact = 'y' * OscEventParser.maxPayload;
      expect(_parse('$esc]9;$exact$bel'), hasLength(1));
      expect(_parse('$esc]9;${exact}z$bel'), isEmpty);
    });

    test('malformed UTF-8 is replaced, not fatal', () {
      final bytes = Uint8List.fromList([
        ..._b('$esc]9;bad '),
        0xff,
        0xc3,
        ..._b(' end$bel'),
      ]);
      final event = OscEventParser().feed(bytes).single as NotifyRequested;
      expect(event.body, startsWith('bad '));
      expect(event.body, endsWith(' end'));
    });

    test('titles (OSC 0/2) and unknown OSCs are ignored; an abandoned '
        'sequence does not swallow the next one', () {
      expect(_parse('$esc]0;title$bel$esc]2;t$st$esc]1337;x$bel'), isEmpty);
      expect(_parse('$esc]133;D;1$esc]133;C$bel'), [const CommandStarted()]);
      expect(_parse('$esc[31m$esc]133;C$bel'), [const CommandStarted()]);
    });

    test('reset drops a half-read sequence', () {
      final parser = OscEventParser();
      expect(parser.feed(_b('$esc]133;')), isEmpty);
      parser.reset();
      expect(parser.feed(_b('C$bel')), isEmpty);
      expect(parser.feed(_b('$esc]133;C$bel')), [const CommandStarted()]);
    });
  });
}
