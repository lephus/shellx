import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

const esc = '\x1b';
const bel = '\x07';
const st = '$esc\\';

String _b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('OSC 99 (A4 D2)', () {
    test('a single title-only chunk becomes the body, with ST or BEL', () {
      expect(OscEventParser().feed(_b('$esc]99;;Xin chào$st')), [
        const KittyNotifyRequested(title: null, body: 'Xin chào'),
      ]);
      expect(OscEventParser().feed(_b('$esc]99;;Hi$bel')), [
        const KittyNotifyRequested(title: null, body: 'Hi'),
      ]);
    });

    test('title (d=0) then body chunk with the same id: one notification', () {
      final p = OscEventParser();
      expect(p.feed(_b('$esc]99;i=1:d=0;Tiêu đề$st')), isEmpty);
      expect(p.feed(_b('$esc]99;i=1:p=body;Nội dung$st')), [
        const KittyNotifyRequested(title: 'Tiêu đề', body: 'Nội dung'),
      ]);
    });

    test('chunks of the same part are appended', () {
      final p = OscEventParser();
      p.feed(_b('$esc]99;i=a:d=0:p=body;Hello $st'));
      expect(p.feed(_b('$esc]99;i=a:p=body;world$st')), [
        const KittyNotifyRequested(title: null, body: 'Hello world'),
      ]);
    });

    test('e=1 payloads are base64 UTF-8', () {
      expect(
        OscEventParser().feed(_b('$esc]99;e=1;${_b64('Build xong ✓')}$st')),
        [const KittyNotifyRequested(title: null, body: 'Build xong ✓')],
      );
    });

    test('broken base64 or UTF-8 drops the chunk', () {
      expect(OscEventParser().feed(_b('$esc]99;e=1;%%%$st')), isEmpty);
      final notUtf8 = base64.encode([0xff, 0xfe]);
      expect(OscEventParser().feed(_b('$esc]99;e=1;$notUtf8$st')), isEmpty);
    });

    test('unknown keys are ignored; unsupported payload types are dropped', () {
      expect(
        OscEventParser().feed(_b('$esc]99;u=2:o=unfocused:a=focus;x$st')),
        [const KittyNotifyRequested(title: null, body: 'x')],
      );
      expect(OscEventParser().feed(_b('$esc]99;i=1:p=?;$st')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]99;i=1:p=icon;abc$st')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]99;nosemicolon$st')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]99;;   $st')), isEmpty);
    });

    test('at most 4 unfinished drafts: the oldest is dropped', () {
      final p = OscEventParser();
      for (var i = 0; i < 5; i++) {
        p.feed(_b('$esc]99;i=$i:d=0;T$i$st'));
      }
      // Draft 0 was evicted: its end alone is a body-only notification.
      expect(p.feed(_b('$esc]99;i=0:p=body;B$st')), [
        const KittyNotifyRequested(title: null, body: 'B'),
      ]);
      expect(p.feed(_b('$esc]99;i=4:p=body;B$st')), [
        const KittyNotifyRequested(title: 'T4', body: 'B'),
      ]);
    });

    test('split at every byte still parses; text cut to 200 characters', () {
      final long = 'á' * 300;
      final bytes = _b('$esc]99;;$long$st');
      final p = OscEventParser();
      final events = [
        for (final b in bytes) ...p.feed(Uint8List.fromList([b])),
      ];
      expect(events, hasLength(1));
      expect((events.single as KittyNotifyRequested).body.runes.length, 200);
    });

    test('reset() forgets drafts', () {
      final p = OscEventParser();
      p.feed(_b('$esc]99;i=1:d=0;T$st'));
      p.reset();
      expect(p.feed(_b('$esc]99;i=1:p=body;B$st')), [
        const KittyNotifyRequested(title: null, body: 'B'),
      ]);
    });
  });

  group('BEL (A4 D3)', () {
    test('a BEL outside escape sequences rings', () {
      expect(OscEventParser().feed(_b('a${bel}b')), [const BellRung()]);
      expect(OscEventParser().feed(_b('$bel$bel')), [
        const BellRung(),
        const BellRung(),
      ]);
    });

    test('BEL ending an OSC, or right after ESC, does not ring', () {
      expect(OscEventParser().feed(_b('$esc]0;title$bel')), isEmpty);
      expect(OscEventParser().feed(_b('$esc]133;C$bel')), [
        const CommandStarted(),
      ]);
      expect(OscEventParser().feed(_b('$esc]9;hi$bel')), [
        const NotifyRequested(title: null, body: 'hi'),
      ]);
      expect(OscEventParser().feed(_b('$esc$bel')), isEmpty);
    });
  });

  test('the command tracker ignores both', () {
    final t = CommandTracker(threshold: () => Duration.zero);
    expect(t.handle(const BellRung()), isNull);
    expect(
      t.handle(const KittyNotifyRequested(title: null, body: 'x')),
      isNull,
    );
    expect(t.running, isFalse);
  });

  test('toString never contains the text (N9)', () {
    expect(
      const KittyNotifyRequested(title: 'secret', body: 'secret').toString(),
      isNot(contains('secret')),
    );
  });
}
