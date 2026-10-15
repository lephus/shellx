import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/tools/tool_embed.dart';
import 'package:shellx_desktop/src/ui/settings/pages/page_parts.dart'
    show settingById;

({ShellxConfig config, List<ConfigProblem> problems}) build(String? value) {
  final problems = <ConfigProblem>[];
  final config = buildShellxConfig(
    ghostty: const [],
    shellx: [
      if (value != null)
        ConfigEntry(file: '/c', line: 1, key: 'tool-embed', value: value),
    ],
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  test('tool-embed: auto by default; auto, on, off; a bad value is a '
      'problem (D7)', () {
    expect(build(null).config.toolEmbed, ToolEmbed.auto);
    expect(build('on').config.toolEmbed, ToolEmbed.on);
    expect(build('off').config.toolEmbed, ToolEmbed.off);
    expect(build('auto').config.toolEmbed, ToolEmbed.auto);
    final bad = build('maybe');
    expect(bad.config.toolEmbed, ToolEmbed.auto);
    expect(bad.problems.single.code, ConfigProblemCode.badValue);
  });

  test('auto embeds on macOS only; on and off say so everywhere (D7, D20)', () {
    const mac = TargetPlatform.macOS;
    const win = TargetPlatform.windows;
    expect(toolsEmbedded(ToolEmbed.auto, mac), isTrue);
    expect(toolsEmbedded(ToolEmbed.auto, win), isFalse);
    expect(toolsEmbedded(ToolEmbed.on, win), isTrue);
    expect(toolsEmbedded(ToolEmbed.on, mac), isTrue);
    expect(toolsEmbedded(ToolEmbed.off, mac), isFalse);
    expect(toolsEmbedded(ToolEmbed.off, win), isFalse);
  });

  test('the row is on Settings › Projects (D22)', () {
    final row = settingById('tool-embed');
    expect(row.page, SettingPage.projects);
    expect(row.choices!.map((c) => c.wire), ['auto', 'on', 'off']);
  });
}
