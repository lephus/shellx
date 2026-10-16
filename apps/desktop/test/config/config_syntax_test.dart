import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';

List<ConfigEntry> parse(String text, List<ConfigProblem> problems) =>
    parseConfigText(text, file: '/c/config', problems: problems);

void main() {
  group('parseConfigText (D5)', () {
    test('key = value, whole-line comments, blanks, CRLF, quotes', () {
      final problems = <ConfigProblem>[];
      final entries = parse(
        '# comment\r\n'
        '\r\n'
        'font-size = 14\r\n'
        '  font-family = "Fira Code"  \n'
        'keybind=super+d=new_split:right\n'
        'theme = a # not a comment\n',
        problems,
      );
      expect(problems, isEmpty);
      expect(
        [for (final e in entries) (e.line, e.key, e.value)],
        [
          (3, 'font-size', '14'),
          (4, 'font-family', 'Fira Code'),
          (5, 'keybind', 'super+d=new_split:right'),
          (6, 'theme', 'a # not a comment'),
        ],
      );
      expect(entries.first.file, '/c/config');
    });

    test('an empty value is kept: it resets the key', () {
      final problems = <ConfigProblem>[];
      final entries = parse('font-family =\nfont-family = ""\n', problems);
      expect([for (final e in entries) e.value], ['', '']);
      expect(problems, isEmpty);
    });

    test('a line without "=" is a syntax error, a bad key is badKey, '
        'the other lines still parse', () {
      final problems = <ConfigProblem>[];
      final entries = parse(
        'font-size 14\nFont-Size = 3\nfont_size = 2\ncursor-style = bar\n',
        problems,
      );
      expect([for (final e in entries) e.key], ['cursor-style']);
      expect(
        [for (final p in problems) (p.line, p.code, p.severity, p.key)],
        [
          (1, ConfigProblemCode.syntax, ConfigSeverity.error, null),
          (2, ConfigProblemCode.badKey, ConfigSeverity.error, 'Font-Size'),
          (3, ConfigProblemCode.badKey, ConfigSeverity.error, 'font_size'),
        ],
      );
    });

    test('a long bad key is truncated to 64 characters', () {
      final problems = <ConfigProblem>[];
      parse('${'K' * 200} = 1\n', problems);
      expect(problems.single.key, hasLength(64));
    });

    test('a lone quote is not stripped', () {
      final entries = parse('theme = "\n', []);
      expect(entries.single.value, '"');
    });
  });

  group('decodeConfigBytes (D5)', () {
    test('UTF-8 with and without BOM', () {
      expect(
        decodeConfigBytes(Uint8List.fromList(utf8.encode('a = é'))),
        'a = é',
      );
      expect(
        decodeConfigBytes(
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('a = 1')]),
        ),
        'a = 1',
      );
    });

    test('UTF-16 with a BOM, both byte orders', () {
      expect(
        decodeConfigBytes(
          Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00, 0x3D, 0x00]),
        ),
        'a=',
      );
      expect(
        decodeConfigBytes(
          Uint8List.fromList([0xFE, 0xFF, 0x00, 0x61, 0x00, 0x3D]),
        ),
        'a=',
      );
    });

    test('lone UTF-16 surrogates and UTF-32 BOMs throw', () {
      expect(
        () => decodeConfigBytes(Uint8List.fromList([0xFF, 0xFE, 0x00, 0xD8])),
        throwsFormatException,
      );
      expect(
        () => decodeConfigBytes(Uint8List.fromList([0xFE, 0xFF, 0xDC, 0x00])),
        throwsFormatException,
      );
      expect(
        decodeConfigBytes(
          Uint8List.fromList([0xFF, 0xFE, 0x3D, 0xD8, 0x00, 0xDE]),
        ),
        '😀',
      );
      expect(
        () => decodeConfigBytes(
          Uint8List.fromList([0xFF, 0xFE, 0x00, 0x00, 0x61, 0x00, 0x00, 0x00]),
        ),
        throwsFormatException,
      );
      expect(
        () => decodeConfigBytes(
          Uint8List.fromList([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x61]),
        ),
        throwsFormatException,
      );
    });

    test('bytes that are not UTF-8, and odd UTF-16, throw FormatException', () {
      expect(
        () => decodeConfigBytes(Uint8List.fromList([0x61, 0xC3, 0x28])),
        throwsFormatException,
      );
      expect(
        () => decodeConfigBytes(Uint8List.fromList([0xFF, 0xFE, 0x61])),
        throwsFormatException,
      );
    });
  });

  group('decodeZigString (D31)', () {
    test('escapes', () {
      expect(decodeZigString(r'git status\n'), 'git status\n');
      expect(decodeZigString(r'\x1b[A'), '\x1b[A');
      expect(decodeZigString(r'\u{1F600}'), '😀');
      expect(decodeZigString(r"""a\\b\"c\'d\te\r"""), 'a\\b"c\'d\te\r');
      expect(decodeZigString('plain'), 'plain');
    });

    test('invalid escapes give null', () {
      for (final bad in [
        r'\q',
        r'\x1',
        r'\xzz',
        r'\u{110000}',
        r'\u{D800}',
        r'\u1234',
        r'\u{12',
        r'abc\',
      ]) {
        expect(decodeZigString(bad), isNull, reason: bad);
      }
    });
  });

  test('ConfigProblem has value equality (the toast compares sets, D36)', () {
    const a = ConfigProblem(
      file: '/c',
      line: 1,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.syntax,
    );
    const b = ConfigProblem(
      file: '/c',
      line: 1,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.syntax,
    );
    expect(a, b);
    expect(<ConfigProblem>{a}..add(b), hasLength(1));
  });

  test('configProblemEnglish fills every placeholder', () {
    final text = configProblemEnglish(
      const ConfigProblem(
        file: '/c',
        line: 3,
        severity: ConfigSeverity.error,
        code: ConfigProblemCode.badValue,
        key: 'font-size',
        value: 'to',
        hint: '9–28',
      ),
    );
    expect(text, 'font-size: “to” is not valid (expected 9–28)');
    // Which placeholders each code's message uses (key, value, hint, detail).
    const uses = <ConfigProblemCode, String>{
      ConfigProblemCode.badKey: 'k',
      ConfigProblemCode.unknownKey: 'k',
      ConfigProblemCode.badValue: 'kvh',
      ConfigProblemCode.outOfRange: 'kvhd',
      ConfigProblemCode.duplicate: 'kd',
      ConfigProblemCode.includeMissing: 'v',
      ConfigProblemCode.includeCycle: 'v',
      ConfigProblemCode.includeLimit: '',
      ConfigProblemCode.problemLimit: 'd',
      ConfigProblemCode.themeNotFound: 'v',
      ConfigProblemCode.fontNotFound: 'v',
      ConfigProblemCode.fontNotMonospace: 'v',
      ConfigProblemCode.lowContrast: 'd',
      ConfigProblemCode.unsupportedValue: 'kvh',
      ConfigProblemCode.notOnThisPlatform: 'k',
      ConfigProblemCode.badTrigger: 'v',
      ConfigProblemCode.unknownAction: 'v',
      ConfigProblemCode.badActionParam: 'vh',
      ConfigProblemCode.reservedTrigger: 'v',
      ConfigProblemCode.plainKeyTrigger: 'v',
      ConfigProblemCode.shellKeyTrigger: 'v',
      ConfigProblemCode.optionKeyTrigger: 'v',
      ConfigProblemCode.altGrTrigger: 'v',
      ConfigProblemCode.missionControlTrigger: 'v',
      ConfigProblemCode.unsupportedPrefix: 'v',
      ConfigProblemCode.sequencePrefixShadows: 'v',
      ConfigProblemCode.sequenceRepeatsPrefix: 'v',
      ConfigProblemCode.unknownCommand: 'v',
    };
    const tokens = {'k': 'KEYX', 'v': 'VALX', 'h': 'HINTX', 'd': 'DETX'};
    for (final code in ConfigProblemCode.values) {
      final message = configProblemEnglish(
        ConfigProblem(
          file: '/c',
          line: 1,
          severity: ConfigSeverity.error,
          code: code,
          key: 'KEYX',
          value: 'VALX',
          hint: 'HINTX',
          detail: 'DETX',
        ),
      );
      expect(message, isNotEmpty, reason: code.name);
      final used = uses[code] ?? '';
      for (final entry in tokens.entries) {
        expect(
          message.contains(entry.value),
          used.contains(entry.key),
          reason: '${code.name} / ${entry.value}',
        );
      }
    }
  });

  test('ConfigProblem.toString has no file path (D40)', () {
    const p = ConfigProblem(
      file: '/home/secret/config',
      line: 4,
      severity: ConfigSeverity.error,
      code: ConfigProblemCode.syntax,
    );
    expect(p.toString(), 'ConfigProblem(syntax line 4)');
  });
}
