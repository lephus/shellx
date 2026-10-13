import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

({ShellxConfig config, List<ConfigProblem> problems}) build(
  List<(String, String)> kv, {
  bool ghostty = false,
}) {
  final problems = <ConfigProblem>[];
  var n = 0;
  final entries = [
    for (final (k, v) in kv)
      ConfigEntry(file: '/c', line: ++n, key: k, value: v),
  ];
  final config = buildShellxConfig(
    ghostty: ghostty ? entries : const [],
    shellx: ghostty ? const [] : entries,
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  group('link-editor (where ⌘-click opens a file path)', () {
    test('auto is the default; each named value is read', () {
      expect(build([]).config.linkEditor, LinkEditor.auto);
      expect(build([('link-editor', '')]).config.linkEditor, LinkEditor.auto);
      for (final v in LinkEditor.values) {
        final r = build([('link-editor', v.name)]);
        expect(r.config.linkEditor, v, reason: v.name);
        expect(r.problems, isEmpty, reason: v.name);
        expect(r.config.origins['link-editor']?.line, 1);
      }
      expect(
        [for (final v in LinkEditor.values) v.name],
        ['auto', 'vscode', 'cursor', 'zed', 'finder'],
      );
    });

    test('anything else is a bad value and keeps what was in effect', () {
      for (final v in ['code', 'VSCode', 'sublime', 'true', 'zed ; x']) {
        final r = build([('link-editor', 'zed'), ('link-editor', v)]);
        expect(r.config.linkEditor, LinkEditor.zed, reason: v);
        expect(r.problems.single.code, ConfigProblemCode.badValue, reason: v);
        expect(r.problems.single.severity, ConfigSeverity.error, reason: v);
        expect(r.problems.single.hint, 'auto, vscode, cursor, zed, finder');
      }
    });

    test('the later line wins', () {
      expect(
        build([
          ('link-editor', 'cursor'),
          ('link-editor', 'finder'),
        ]).config.linkEditor,
        LinkEditor.finder,
      );
    });

    test('a Ghostty file never sets it', () {
      expect(kGhosttyKeys.contains('link-editor'), isFalse);
      expect(
        build([('link-editor', 'zed')], ghostty: true).config.linkEditor,
        LinkEditor.auto,
      );
    });
  });
}
