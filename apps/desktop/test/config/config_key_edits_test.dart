import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_key_edits.dart';
import 'package:shellx_desktop/src/config/config_writer.dart';

String set(String text, String key, String value) =>
    applyKeyEdits(text, [SetKey(key, value)]);
String reset(String text, String key, {bool explicit = false}) =>
    applyKeyEdits(text, [ResetKey(key, explicitDefault: explicit)]);

Matcher refuses([ConfigWriteRefusal? why]) => throwsA(
  isA<ConfigWriteRefused>().having(
    (e) => e.reason,
    'reason',
    why ?? isA<ConfigWriteRefusal>(),
  ),
);

void main() {
  group('SetKey', () {
    test('changes the value of the user line in place, nothing else', () {
      const before = '# my config\nfont-size = 13\n\ntheme = Dracula\n';
      expect(
        set(before, 'font-size', '15'),
        '# my config\nfont-size = 15\n\ntheme = Dracula\n',
      );
    });

    test('keeps the spelling and spacing of the user line', () {
      expect(set('font-size=13\n', 'font-size', '15'), 'font-size=15\n');
      expect(
        set('  font-size  =   13\n', 'font-size', '15'),
        '  font-size  =   15\n',
      );
      expect(set('font-size =\n', 'font-size', '15'), 'font-size = 15\n');
    });

    test(
      'with two lines for the key, the last (the one in effect) is edited',
      () {
        const before = 'font-size = 11\nfont-size = 13\n';
        expect(
          set(before, 'font-size', '15'),
          'font-size = 11\nfont-size = 15\n',
        );
      },
    );

    test('a key with no line goes into a new managed block at the end', () {
      const before = '# my config\ntheme = Dracula\n';
      final after = set(before, 'font-size', '15');
      expect(after.startsWith(before), isTrue, reason: 'every old byte kept');
      expect(after, contains('$kSettingsStart\n'));
      expect(after, contains('font-size = 15\n'));
      expect(after.trimRight().endsWith(kSettingsEnd), isTrue);
    });

    test('a second key joins the existing block; the same key is replaced '
        'there', () {
      var t = set('', 'font-size', '15');
      t = set(t, 'cursor-style', 'bar');
      t = set(t, 'font-size', '16');
      expect(
        RegExp(r'^font-size = ', multiLine: true).allMatches(t),
        hasLength(1),
      );
      expect(t, contains('font-size = 16'));
      expect(t, contains('cursor-style = bar'));
      expect(RegExp(RegExp.escape(kSettingsStart)).allMatches(t), hasLength(1));
    });

    test('the line in effect wins: a user line written after our block is '
        'the one edited', () {
      var t = set('', 'font-size', '15');
      t = '$t\nfont-size = 20\n';
      final after = set(t, 'font-size', '22');
      expect(after, contains('font-size = 15\n'), reason: 'ours is shadowed');
      expect(after.trimRight().endsWith('font-size = 22'), isTrue);
    });

    test('CRLF files stay CRLF everywhere, including the new block', () {
      const before = 'theme = Dracula\r\nfont-size = 13\r\n';
      final after = set(set(before, 'font-size', '15'), 'cursor-style', 'bar');
      expect(
        after.contains(RegExp(r'(?<!\r)\n')),
        isFalse,
        reason: 'no bare LF',
      );
      expect(after, startsWith('theme = Dracula\r\nfont-size = 15\r\n'));
    });

    test('a mixed-ending file keeps each line\'s own ending', () {
      const before = 'a = 1\r\nfont-size = 13\nb = 2\r\n';
      expect(
        set(before, 'font-size', '15'),
        'a = 1\r\nfont-size = 15\nb = 2\r\n',
      );
    });

    test('a file without a final newline gets one before the block', () {
      final after = set('theme = Dracula', 'font-size', '15');
      expect(after, startsWith('theme = Dracula\n'));
    });

    test('the last line without a newline is edited without adding one', () {
      expect(
        set('a = 1\nfont-size = 13', 'font-size', '15'),
        'a = 1\nfont-size = 15',
      );
    });

    test('lines of the managed keybind block are never touched', () {
      const before =
          '# >>> shellx-managed keybinds >>>\nkeybind = super+d=ignore\n'
          '# <<< shellx-managed keybinds <<<\n';
      final after = set(before, 'font-size', '15');
      expect(after.startsWith(before), isTrue);
      expect(after, contains('font-size = 15'));
    });

    test('a settings-looking line inside the keybind block is not ours', () {
      const before =
          '# >>> shellx-managed keybinds >>>\nfont-size = 9\n'
          '# <<< shellx-managed keybinds <<<\n';
      final after = set(before, 'font-size', '15');
      expect(after.startsWith(before), isTrue);
      expect(after, contains('\nfont-size = 15\n'));
    });

    test('a quoted comment is not a key line', () {
      const before = '# font-size = 99\n';
      final after = set(before, 'font-size', '15');
      expect(after.startsWith(before), isTrue);
      expect(after, contains('\nfont-size = 15\n'));
    });

    test('an empty value writes `key =`', () {
      expect(set('font-size = 13\n', 'font-size', ''), 'font-size =\n');
      expect(set('', 'font-size', ''), contains('\nfont-size =\n'));
    });

    test('a damaged block (a marker alone) is refused, the text untouched', () {
      const before = '$kSettingsStart\nfont-size = 15\n';
      expect(
        () => set(before, 'cursor-style', 'bar'),
        refuses(ConfigWriteRefusal.damagedBlock),
      );
    });

    test('two blocks, an end before its start, or overlapping blocks are '
        'damaged', () {
      const one = '$kSettingsStart\na = 1\n$kSettingsEnd\n';
      for (final bad in [
        '$one$one',
        '$kSettingsEnd\n$kSettingsStart\n',
        '$kManagedStart\n$kSettingsStart\n$kManagedEnd\n$kSettingsEnd\n',
        '$kManagedStart\nkeybind = a=b\n',
      ]) {
        expect(() => set(bad, 'font-size', '1'), refuses(), reason: bad);
        expect(() => reset(bad, 'font-size'), refuses(), reason: bad);
      }
    });

    test(
      'a marker with extra text, or quoted in a comment, is not a marker',
      () {
        const before =
            '# see: $kSettingsStart\n$kSettingsEnd extra\nfont-size = 13\n';
        expect(
          set(before, 'font-size', '15'),
          '# see: $kSettingsStart\n$kSettingsEnd extra\nfont-size = 15\n',
        );
      },
    );

    test('a value with a line break would write a second line: refused', () {
      expect(
        () => set('', 'font-family', 'A\nkeybind = x=ignore'),
        throwsArgumentError,
      );
      expect(() => set('', 'font-family', 'A\rB'), throwsArgumentError);
    });

    test('a key that is not a config key name is refused', () {
      for (final k in ['', 'Font Size', 'a=b', '#x', 'a\nb', '-a']) {
        expect(() => set('', k, '1'), throwsArgumentError, reason: k);
      }
    });

    test(
      'a file with a lone carriage return (read as one line) is refused',
      () {
        expect(
          () => set('a = 1\rfont-size = 13\r', 'font-size', '15'),
          refuses(ConfigWriteRefusal.loneCarriageReturn),
        );
      },
    );

    test('toString never shows the key or value', () {
      expect(const SetKey('font-family', 'Secret').toString(), '…');
      expect(const ResetKey('font-family').toString(), '…');
    });
  });

  group('ResetKey', () {
    test('comments out the user line instead of deleting it', () {
      const before = 'theme = Dracula\nfont-size = 13\n';
      expect(reset(before, 'font-size'), 'theme = Dracula\n# font-size = 13\n');
    });

    test('keeps the indentation and the line ending when commenting out', () {
      expect(reset('  font-size=13\r\n', 'font-size'), '  # font-size=13\r\n');
    });

    test(
      'comments out every line of the key (an older one would take over)',
      () {
        const before = 'font-size = 11\nfont-size = 13\n';
        expect(
          reset(before, 'font-size'),
          '# font-size = 11\n# font-size = 13\n',
        );
      },
    );

    test('removes the managed line; an empty block disappears', () {
      final withBlock = set('theme = X\n', 'font-size', '15');
      final back = reset(withBlock, 'font-size');
      expect(back.trimRight(), 'theme = X');
      expect(back.contains(kSettingsStart), isFalse);
    });

    test('other keys of the block stay', () {
      var t = set(set('', 'font-size', '15'), 'cursor-style', 'bar');
      t = reset(t, 'font-size');
      expect(t, contains('cursor-style = bar'));
      expect(t, isNot(contains('font-size')));
      expect(t, contains(kSettingsStart));
    });

    test('explicitDefault writes an empty value so a Ghostty value stops '
        'applying', () {
      final after = reset('', 'font-size', explicit: true);
      expect(after, contains('font-size =\n'));
    });

    test('a key that is not there changes nothing, an empty block of the '
        'user\'s included', () {
      const before = 'theme = X\n';
      expect(reset(before, 'font-size'), before);
      const empty = '$kSettingsStart\n$kSettingsEnd\n';
      expect(reset(empty, 'font-size'), empty);
    });

    test('a block with the user\'s own comment in it is not removed', () {
      final t = set(
        '',
        'font-size',
        '15',
      ).replaceFirst('$kSettingsEnd\n', '# my note\n$kSettingsEnd\n');
      final back = reset(t, 'font-size');
      expect(back, contains('# my note'));
      expect(back, contains(kSettingsStart));
    });
  });

  test(
    'set then reset gives back the original (modulo trailing blank lines)',
    () {
      const original = '# hello\r\ntheme = Dracula\r\n\r\n# end\r\n';
      final round = reset(set(original, 'font-size', '15'), 'font-size');
      expect(round.trimRight(), original.trimRight());
    },
  );

  test('property: setting any key keeps every other line byte for byte', () {
    const lines = [
      'a = 1',
      '# c',
      '',
      'theme = X',
      'font-size = 13',
      'keybind = a=b',
    ];
    final text = '${lines.join('\n')}\n';
    final after = set(text, 'font-size', '20');
    final kept = after.split('\n')..remove('font-size = 20');
    expect(kept, equals(text.split('\n')..remove('font-size = 13')));
  });

  group('keys the Settings never edits', () {
    test('keybind and config-file are refused', () {
      for (final key in ['keybind', 'config-file']) {
        expect(() => set('a = 1\n', key, 'x'), throwsArgumentError);
        expect(() => reset('a = 1\n', key), throwsArgumentError);
      }
    });
  });

  group('hostile files', () {
    test('an include line and a Ghostty-style file are left alone', () {
      const before = 'config-file = ?extra\ntheme = X\n';
      final after = set(before, 'font-size', '15');
      expect(after.startsWith(before), isTrue);
    });

    test('a 200 KiB file with the key on the last line, and 20 000 lines', () {
      final big = StringBuffer();
      for (var i = 0; i < 20000; i++) {
        big.write('# filler line number $i\n');
      }
      final text = '${big}font-size = 13\n';
      final sw = Stopwatch()..start();
      final after = set(text, 'font-size', '15');
      final back = reset(after, 'font-size');
      expect(sw.elapsedMilliseconds, lessThan(2000));
      expect(after, '${big}font-size = 15\n');
      expect(back, '$big# font-size = 15\n');
    });

    test('one enormous line is edited without touching its neighbours', () {
      final long = 'x' * 200000;
      final text = '# $long\nfont-size = 13\n# $long\n';
      expect(
        set(text, 'font-size', '15'),
        '# $long\nfont-size = 15\n# $long\n',
      );
    });

    test('a stray U+FEFF and non-ASCII text survive', () {
      const before = '\u{FEFF}# phông chữ — 日本語 😀\nfont-size = 13\n';
      expect(
        set(before, 'font-size', '15'),
        '\u{FEFF}# phông chữ — 日本語 😀\nfont-size = 15\n',
      );
    });

    test('an empty file and a file of only blank lines', () {
      expect(set('', 'font-size', '15'), contains('font-size = 15'));
      expect(set('\n\n', 'font-size', '15'), startsWith('\n\n'));
      expect(reset('', 'font-size'), '');
    });
  });

  group('fuzz: only the edited keys\' lines change', () {
    const keys = ['font-size', 'cursor-style', 'theme', 'scrollback-limit'];
    String strip(String line) => line.replaceFirst(RegExp(r'^\s*# ?'), '');
    bool isTouched(String line, Set<String> touched) {
      final t = strip(line.trim());
      final eq = t.indexOf('=');
      return eq > 0 && touched.contains(t.substring(0, eq).trim());
    }

    List<String> filtered(String text, Set<String> touched) => [
      for (final raw in text.split('\n'))
        if (raw.trim().isNotEmpty &&
            raw.trim() != kSettingsStart &&
            raw.trim() != kSettingsEnd &&
            !raw.contains('Written by ShellX Settings') &&
            !isTouched(raw, touched))
          raw.trimRight(),
    ];

    test('300 random files, random edit sequences', () {
      final rnd = Random(20261007);
      for (var round = 0; round < 300; round++) {
        final crlf = rnd.nextBool();
        final eol = crlf ? '\r\n' : '\n';
        final parts = <String>[];
        for (var i = 0, n = rnd.nextInt(14); i < n; i++) {
          parts.add(switch (rnd.nextInt(8)) {
            0 => '# comment ${rnd.nextInt(99)}',
            1 => '',
            2 => '${keys[rnd.nextInt(keys.length)]} = ${rnd.nextInt(99)}',
            3 => 'keybind = super+${rnd.nextInt(9)}=new_tab',
            4 => '# ${keys[rnd.nextInt(keys.length)]} = commented',
            5 => 'config-file = ?inc${rnd.nextInt(3)}',
            6 => '# note $kSettingsStart',
            _ => 'zzz-other = ${rnd.nextInt(5)}',
          });
        }
        if (rnd.nextInt(4) == 0) {
          parts
            ..add(kManagedStart)
            ..add('keybind = ctrl+${rnd.nextInt(9)}=new_tab')
            ..add(kManagedEnd);
        }
        var text = parts.map((p) => '$p$eol').join();
        if (rnd.nextInt(5) == 0 && text.isNotEmpty) {
          text = text.substring(0, text.length - eol.length);
        }
        final edits = <KeyEdit>[];
        for (var i = 0, n = 1 + rnd.nextInt(5); i < n; i++) {
          final k = keys[rnd.nextInt(keys.length)];
          edits.add(
            rnd.nextInt(3) == 0
                ? ResetKey(k, explicitDefault: rnd.nextBool())
                : SetKey(k, '${rnd.nextInt(50)}'),
          );
        }
        final touched = {for (final e in edits) e.key};
        final after = applyKeyEdits(text, edits);
        expect(
          filtered(after, touched),
          filtered(text, touched),
          reason: 'round $round\n${text.replaceAll('\r', '␍')}\n$edits',
        );
        if (crlf && text.contains('\r\n')) {
          expect(
            after.contains(RegExp(r'(?<!\r)\n')),
            isFalse,
            reason: 'CRLF kept, round $round',
          );
        }
        // The keybind block is byte for byte as it was.
        final kb = RegExp(
          '${RegExp.escape(kManagedStart)}[\\s\\S]*?${RegExp.escape(kManagedEnd)}',
        );
        expect(kb.firstMatch(after)?.group(0), kb.firstMatch(text)?.group(0));
        // Idempotent: the same Set twice is the same file.
        final again = applyKeyEdits(after, [
          for (final e in edits.whereType<SetKey>()) e,
        ]);
        expect(
          applyKeyEdits(again, [for (final e in edits.whereType<SetKey>()) e]),
          again,
        );
      }
    });
  });
}
