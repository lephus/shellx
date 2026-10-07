import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/memory_config_fs.dart';
import 'support/cli_container.dart';

void main() {
  late MemoryConfigFs fs;
  late FakeLocalSessions local;
  late ProviderContainer c;
  final paths = testConfigPaths();

  setUp(() {
    fs = MemoryConfigFs();
    local = FakeLocalSessions();
    c = cliContainer(local, overrides: configOverrides(fs));
  });

  Future<Map<String, Object?>> call(
    String type, [
    Map<String, Object?> fields = const {},
  ]) => c
      .read(uiCommandHandlerProvider)
      .handle(MuxMessage(type, q: 1, fields: fields));

  test('the cap is advertised (A7 D4)', () {
    expect(kCliCaps, contains('ui.config'));
  });

  test('check reports the files as they are, without applying (D39)', () async {
    fs.write(paths.shellx, 'font-size = to\n');
    final r = await call(CliType.uiConfigCheck);
    final p = (r['problems']! as List).single as Map;
    expect(p['file'], paths.shellx);
    expect(p['line'], 1);
    expect(p['severity'], 'error');
    expect(p['code'], 'badValue');
    expect(p['key'], 'font-size');
    expect(p['message'], 'font-size: “to” is not valid (expected 9–28)');
    expect(c.read(shellxConfigProvider).generation, 0);
    expect(c.read(shellxConfigProvider).config.fontSize, isNull);
  });

  test(
    'check on a clean file: no problems, no key field absent noise',
    () async {
      fs.write(paths.shellx, 'font-size = 16\n');
      final r = await call(CliType.uiConfigCheck);
      expect(r['problems'], isEmpty);
    },
  );

  test('every problem code has an English message (D39)', () {
    for (final code in ConfigProblemCode.values) {
      final text = configProblemEnglish(
        ConfigProblem(
          file: 'f',
          line: 1,
          severity: ConfigSeverity.warning,
          code: code,
          key: 'k',
          value: 'v',
          hint: 'h',
          detail: 'd',
        ),
      );
      expect(text, isNotEmpty, reason: code.name);
    }
  });

  test('every problem code reads the same over the CLI (D39)', () async {
    fs.write(
      paths.shellx,
      'font-size = to\nno-such = 1\nkeybind = super+q=new_tab\nbroken\n',
    );
    final problems = await c.read(shellxConfigProvider.notifier).check();
    expect(problems, isNotEmpty);
    final r = await call(CliType.uiConfigCheck);
    final got = (r['problems']! as List).cast<Map>();
    expect(got.map((p) => p['message']), [
      for (final p in problems) configProblemEnglish(p),
    ]);
  });

  test('reload applies and answers with the new problems', () async {
    fs.write(paths.shellx, 'font-size = 16\n');
    final r = await call(CliType.uiConfigReload);
    expect(r['problems'], isEmpty);
    expect(r['generation'], 1);
    expect(c.read(shellxConfigProvider).config.fontSize, 16);
    expect(c.read(shellxConfigProvider).lastLoad!.manual, isTrue);
  });

  test(
    'reload with errors still applies what is valid and lists them',
    () async {
      fs.write(paths.shellx, 'font-size = 16\nno-such = 1\n');
      final r = await call(CliType.uiConfigReload);
      final p = (r['problems']! as List).single as Map;
      expect(p['code'], 'unknownKey');
      expect(c.read(shellxConfigProvider).config.fontSize, 16);
    },
  );

  test('show: values with their source; --defaults: the template', () async {
    fs.write(paths.shellx, '\nfont-size = 16\n');
    await call(CliType.uiConfigReload);
    final r = await call(CliType.uiConfigShow);
    final values = (r['values']! as List).cast<Map>();
    final size = values.firstWhere((v) => v['key'] == 'font-size');
    expect(size['value'], '16');
    expect(size['source'], '${paths.shellx}:2');
    expect(
      values.firstWhere((v) => v['key'] == 'cursor-style')['source'],
      'default',
    );
    expect((r['files']! as Map)['shellx'], paths.shellx);
    final d = await call(CliType.uiConfigShow, {'defaults': true});
    expect(d['template'], contains('# font-size = 13'));
    expect(d.containsKey('values'), isFalse);
  });

  test('show never carries the text of the file', () async {
    fs.write(paths.shellx, '# my secret note\ncommand = Go = ssh me@host\n');
    await call(CliType.uiConfigReload);
    final r = await call(CliType.uiConfigShow);
    expect(r.toString(), isNot(contains('secret note')));
  });

  test(
    'show prints a command as its value only, nothing else of the file',
    () async {
      fs.write(
        paths.shellx,
        '# private remark\ncommand = Go = ssh me@host\nsnippet = Hi = echo hi\n',
      );
      await call(CliType.uiConfigReload);
      final r = await call(CliType.uiConfigShow);
      final values = (r['values']! as List).cast<Map>();
      final cmd = values.firstWhere((v) => v['key'] == 'command');
      expect(cmd['value'], 'Go = ssh me@host');
      expect(cmd['source'], '${paths.shellx}:2');
      expect(cmd.keys, unorderedEquals(['key', 'value', 'source']));
      expect(
        values.firstWhere((v) => v['key'] == 'snippet')['value'],
        'Hi = echo hi',
      );
      expect(r.toString(), isNot(contains('private remark')));
    },
  );

  test('new-tab without --cwd follows working-directory (D21)', () async {
    fs.write(paths.shellx, 'working-directory = /tmp/w\n');
    await call(CliType.uiConfigReload);
    await call(CliType.uiTabNew);
    expect(local.openCwds.last, '/tmp/w');
    await call(CliType.uiTabNew, {'cwd': '/x'});
    expect(local.openCwds.last, '/x');
    await call(CliType.uiWorkspaceNew);
    expect(local.openCwds.last, '/tmp/w');
  });

  test('new-tab without a configured directory starts at home', () async {
    await call(CliType.uiTabNew);
    expect(local.openCwds.last, isNull);
    expect(c.read(terminalTabsProvider).tabs, hasLength(1));
  });
}
