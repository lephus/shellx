import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';

const String block = '# >>> ShellX >>>\necho wrapped\n# <<< ShellX <<<\n';

void main() {
  late Directory dir;
  const editor = ConfigFileEditor();

  setUp(() => dir = Directory.systemTemp.createTempSync('shellx-config-'));
  tearDown(() => dir.deleteSync(recursive: true));

  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';
  ConfigTarget target(String name, {bool create = false, String eol = '\n'}) =>
      ConfigTarget(
        path: path(name),
        block: block,
        create: create,
        newFileEol: eol,
      );

  test('inserts the block at the top and backs the file up once', () async {
    File(path('.zshrc')).writeAsStringSync('export A=1\n');
    final edit = await editor.install(target('.zshrc'));
    expect(edit.changed, isTrue);
    expect(File(path('.zshrc')).readAsStringSync(), '${block}export A=1\n');
    expect(
      File(path('.zshrc.shellx-backup')).readAsStringSync(),
      'export A=1\n',
    );

    // Second install: nothing to change; the backup is never overwritten.
    File(path('.zshrc')).writeAsStringSync('${block}export A=2\n');
    final again = await editor.install(target('.zshrc'));
    expect(again.changed, isFalse);
    expect(File(path('.zshrc')).readAsStringSync(), '${block}export A=2\n');
    expect(
      File(path('.zshrc.shellx-backup')).readAsStringSync(),
      'export A=1\n',
    );
  });

  test('an existing backup is never overwritten', () async {
    File(path('.zshrc')).writeAsStringSync('new\n');
    File(path('.zshrc.shellx-backup')).writeAsStringSync('older backup\n');
    final edit = await editor.install(target('.zshrc'));
    expect(
      File(path('.zshrc.shellx-backup')).readAsStringSync(),
      'older backup\n',
    );
    await edit.undo();
    expect(
      File(path('.zshrc.shellx-backup')).readAsStringSync(),
      'older backup\n',
    );
    expect(File(path('.zshrc')).readAsStringSync(), 'new\n');
  });

  test('a missing file is created only when the target allows it', () async {
    final skipped = await editor.install(target('.bash_profile'));
    expect(skipped.changed, isFalse);
    expect(File(path('.bash_profile')).existsSync(), isFalse);

    final created = await editor.install(target('.zshrc', create: true));
    expect(created.changed, isTrue);
    expect(File(path('.zshrc')).readAsStringSync(), block);
    expect(File(path('.zshrc.shellx-backup')).existsSync(), isFalse);
  });

  test('a new file gets the target\'s line ending and missing folders', () async {
    final t = ConfigTarget(
      path: path(
        'Documents${Platform.pathSeparator}PowerShell${Platform.pathSeparator}profile.ps1',
      ),
      block: block,
      create: true,
      newFileEol: '\r\n',
    );
    await editor.install(t);
    expect(File(t.path).readAsStringSync(), block.replaceAll('\n', '\r\n'));
  });

  test('undo restores the original bytes and removes its backup', () async {
    final original = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('Tiếng Việt\r\n'),
    ]);
    File(path('profile.ps1')).writeAsBytesSync(original);
    final edit = await editor.install(target('profile.ps1'));
    expect(File(path('profile.ps1')).readAsBytesSync(), isNot(original));
    await edit.undo();
    expect(File(path('profile.ps1')).readAsBytesSync(), original);
    expect(File(path('profile.ps1.shellx-backup')).existsSync(), isFalse);
  });

  test('undo deletes a file it created', () async {
    final edit = await editor.install(target('.zshrc', create: true));
    await edit.undo();
    expect(File(path('.zshrc')).existsSync(), isFalse);
  });

  test('CRLF and UTF-16 files keep their format', () async {
    final bytes = Uint8List.fromList([
      0xFF,
      0xFE,
      0x41,
      0x00,
      0x0D,
      0x00,
      0x0A,
      0x00,
    ]);
    File(path('p.ps1')).writeAsBytesSync(bytes);
    await editor.install(target('p.ps1'));
    final written = File(path('p.ps1')).readAsBytesSync();
    expect(written.sublist(0, 4), [0xFF, 0xFE, 0x23, 0x00]); // BOM, '#'
    expect(await editor.remove(path('p.ps1')), isTrue);
    expect(File(path('p.ps1')).readAsBytesSync(), bytes);
  });

  test('remove deletes only the block and keeps the rest', () async {
    File(path('.bashrc')).writeAsStringSync('a\n${block}b\n');
    expect(await editor.remove(path('.bashrc')), isTrue);
    expect(File(path('.bashrc')).readAsStringSync(), 'a\nb\n');
    expect(await editor.remove(path('.bashrc')), isFalse);
    expect(await editor.remove(path('missing')), isFalse);
  });

  test('installedBlock reads the block back', () async {
    expect(await editor.installedBlock(path('missing')), isNull);
    File(path('.zshrc')).writeAsStringSync('x\n');
    expect(await editor.installedBlock(path('.zshrc')), isNull);
    await editor.install(target('.zshrc'));
    expect(await editor.installedBlock(path('.zshrc')), block);
  });

  test(
    'a symlinked file is edited through the link; the link stays',
    () async {
      File(path('dotfiles-zshrc')).writeAsStringSync('x\n');
      Link(path('.zshrc')).createSync(path('dotfiles-zshrc'));
      final edit = await editor.install(target('.zshrc'));
      expect(FileSystemEntity.isLinkSync(path('.zshrc')), isTrue);
      expect(File(path('dotfiles-zshrc')).readAsStringSync(), '${block}x\n');
      await edit.undo();
      expect(FileSystemEntity.isLinkSync(path('.zshrc')), isTrue);
      expect(File(path('dotfiles-zshrc')).readAsStringSync(), 'x\n');
      expect(await editor.remove(path('.zshrc')), isFalse);
    },
    skip: Platform.isWindows ? 'symlinks need privileges on Windows' : false,
  );
}
