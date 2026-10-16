import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_key_edits.dart';
import 'package:shellx_desktop/src/config/config_writer.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';

import '../support/memory_config_fs.dart';

KeyChord c(String t) => parseKeyChord(t)!;

/// The `keybind = …` lines (the markers also contain "keybinds").
int keybindLines(String text) =>
    RegExp(r'^keybind =', multiLine: true).allMatches(text).length;

void main() {
  const user = '# mine\nfont-size = 14\r\nkeybind = super+k=new_tab\n';

  test('add appends a managed block; bytes before it are untouched (D32)', () {
    final out = applyBindingEdits(user, [
      AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
    ]);
    expect(out.startsWith(user), isTrue);
    expect(
      out.substring(user.length),
      '$kManagedStart\nkeybind = ctrl+alt+n=new_tab\n$kManagedEnd\n',
    );
  });

  test('a new block takes the line ending of the line before it', () {
    final out = applyBindingEdits('a = 1\nb = 2\r\n', [
      AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
    ]);
    expect(
      out,
      'a = 1\nb = 2\r\n$kManagedStart\r\nkeybind = ctrl+alt+n=new_tab\r\n$kManagedEnd\r\n',
    );
  });

  test('an edited block takes the line ending of the line before it', () {
    final text =
        'a = 1\r\nb = 2\n$kManagedStart\nkeybind = super+j=new_tab\n$kManagedEnd\r\nc = 3\r\n';
    final out = applyBindingEdits(text, [
      AddBinding(c('super+y'), const KeyAction('new_tab')),
    ]);
    expect(
      out,
      'a = 1\r\nb = 2\n$kManagedStart\nkeybind = super+j=new_tab\nkeybind = super+y=new_tab\n$kManagedEnd\nc = 3\r\n',
    );
  });

  test('a start marker without an end is refused, never appended to', () {
    expect(
      () => applyBindingEdits('a = 1\n$kManagedStart\nkeybind = x\n', [
        AddBinding(c('super+y'), const KeyAction('new_tab')),
      ]),
      throwsA(
        isA<ConfigWriteRefused>().having(
          (e) => e.reason,
          'reason',
          ConfigWriteRefusal.damagedBlock,
        ),
      ),
    );
  });

  test('an end marker without a start, or a second block, is refused', () {
    final add = [AddBinding(c('super+y'), const KeyAction('new_tab'))];
    for (final text in [
      'a = 1\n$kManagedEnd\n',
      '$kManagedStart\n$kManagedEnd\nx = 1\n$kManagedStart\n$kManagedEnd\n',
      '$kManagedEnd\n$kManagedStart\n',
    ]) {
      expect(
        () => applyBindingEdits(text, add),
        throwsA(isA<ConfigWriteRefused>()),
        reason: text,
      );
    }
  });

  test('a file without a final newline gets one before the block', () {
    final out = applyBindingEdits('font-size = 14', [
      AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
    ]);
    expect(
      out,
      'font-size = 14\n$kManagedStart\nkeybind = ctrl+alt+n=new_tab\n$kManagedEnd\n',
    );
  });

  test(
    'the same chord again replaces its line; remove; unbind for defaults',
    () {
      var text = applyBindingEdits('', [
        AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
      ]);
      text = applyBindingEdits(text, [
        AddBinding(c('ctrl+alt+n'), const KeyAction('new_workspace')),
      ]);
      expect(keybindLines(text), 1);
      expect(text, contains('keybind = ctrl+alt+n=new_workspace'));
      text = applyBindingEdits(text, [
        RemoveBinding(c('ctrl+alt+n'), isDefault: false),
      ]);
      expect(text, isEmpty); // the block disappears with its last line
      text = applyBindingEdits('', [
        RemoveBinding(c('super+t'), isDefault: true),
      ]);
      expect(text, contains('keybind = super+t=unbind'));
    },
  );

  test(
    'remove writes an unbind when a user line outside the block binds the chord',
    () {
      final text = applyBindingEdits(user, [
        RemoveBinding(c('super+k'), isDefault: false),
      ]);
      expect(text, contains('keybind = super+k=unbind'));
      expect(text.startsWith(user), isTrue);
    },
  );

  test('reset drops the action\'s lines and the unbinds of its defaults', () {
    var text = applyBindingEdits('', [
      RemoveBinding(c('super+t'), isDefault: true),
      AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
      AddBinding(c('ctrl+alt+w'), const KeyAction('new_workspace')),
    ]);
    text = applyBindingEdits(text, [
      ResetAction(const KeyAction('new_tab'), [c('super+t')]),
    ]);
    expect(text, isNot(contains('super+t')));
    expect(text, isNot(contains('ctrl+alt+n')));
    expect(text, contains('ctrl+alt+w=new_workspace'));
  });

  test('an existing block in the middle stays in place', () {
    final text =
        'a = 1\n$kManagedStart\nkeybind = super+j=new_tab\n$kManagedEnd\nb = 2\n';
    final out = applyBindingEdits(text, [
      AddBinding(c('super+y'), const KeyAction('new_tab')),
    ]);
    expect(
      out,
      'a = 1\n$kManagedStart\nkeybind = super+j=new_tab\nkeybind = super+y=new_tab\n$kManagedEnd\nb = 2\n',
    );
    expect(managedLineRange(out), (first: 2, last: 5));
  });

  test('markers quoted in a comment are not the block', () {
    final text = '# see "$kManagedStart" in the docs\na = 1\n';
    final out = applyBindingEdits(text, [
      AddBinding(c('super+y'), const KeyAction('new_tab')),
    ]);
    expect(out.startsWith(text), isTrue);
    expect(managedLineRange(text), isNull);
    expect(managedLineRange(out), (first: 3, last: 5));
  });

  test('a comment the user wrote inside the block survives an edit', () {
    final text =
        '$kManagedStart\n# my note\nkeybind = super+j=new_tab\n$kManagedEnd\n';
    final out = applyBindingEdits(text, [
      AddBinding(c('super+y'), const KeyAction('new_tab')),
    ]);
    expect(out, contains('# my note\n'));
    expect(out, contains('keybind = super+j=new_tab\n'));
  });

  test('CRLF files keep CRLF inside the rewritten block too', () {
    final text =
        'a = 1\r\n$kManagedStart\r\nkeybind = super+j=new_tab\r\n$kManagedEnd\r\nb = 2\r\n';
    final out = applyBindingEdits(text, [
      AddBinding(c('super+y'), const KeyAction('new_tab')),
    ]);
    expect(out.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(out.startsWith('a = 1\r\n'), isTrue);
    expect(out.endsWith('$kManagedEnd\r\nb = 2\r\n'), isTrue);
  });

  group('ConfigFileWriter', () {
    test(
      'creates from the template; keeps a UTF-8 BOM; refuses UTF-16',
      () async {
        final fs = MemoryConfigFs();
        final writer = ConfigFileWriter(fs);
        await writer.edit('/c/config', [
          AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
        ], template: '# template\n');
        expect(fs.text('/c/config'), startsWith('# template\n$kManagedStart'));
        fs.writeBytes('/c/bom', [0xEF, 0xBB, 0xBF, ...utf8.encode('a = 1\n')]);
        await writer.edit('/c/bom', [
          AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
        ], template: '');
        expect(fs.files['/c/bom']!.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
        expect(fs.files['/c/bom']!.sublist(3, 3 + 6), utf8.encode('a = 1\n'));
        fs.writeBytes('/c/u16', [0xFF, 0xFE, 0x61, 0x00]);
        await expectLater(
          writer.edit('/c/u16', [
            AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
          ], template: ''),
          throwsA(isA<ConfigWriteRefused>()),
        );
        expect(
          fs.files['/c/u16'],
          Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00]),
        );
      },
    );

    final add = [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))];

    test(
      'a file changed after it was read is refused, never clobbered',
      () async {
        final fs = MemoryConfigFs()..write('/c/config', 'a = 1\n');
        fs.beforeReplace = (path) => fs.write(path, 'a = 1\nb = 2\n');
        await expectLater(
          ConfigFileWriter(fs).edit('/c/config', add, template: ''),
          throwsA(
            isA<ConfigWriteRefused>().having(
              (e) => e.reason,
              'reason',
              ConfigWriteRefusal.changed,
            ),
          ),
        );
        expect(fs.text('/c/config'), 'a = 1\nb = 2\n');
      },
    );

    test('a file created after it was found missing is refused', () async {
      final fs = MemoryConfigFs();
      fs.beforeReplace = (path) => fs.write(path, 'mine = 1\n');
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: '# t\n'),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(fs.text('/c/config'), 'mine = 1\n');
    });

    test('a file over the size cap is refused with a reason', () async {
      final fs = MemoryConfigFs()
        ..writeBytes('/c/config', Uint8List(kConfigMaxBytes + 1));
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: ''),
        throwsA(
          isA<ConfigWriteRefused>().having(
            (e) => e.reason,
            'reason',
            ConfigWriteRefusal.tooLarge,
          ),
        ),
      );
      expect(fs.replaced, isEmpty);
    });

    test('an edit that would grow the file past the cap is refused', () async {
      final fs = MemoryConfigFs()
        ..writeBytes(
          '/c/config',
          Uint8List(kConfigMaxBytes - 4)
            ..fillRange(0, kConfigMaxBytes - 4, 0x23),
        );
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: ''),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(fs.replaced, isEmpty);
    });

    test('an unreadable file is refused (the read error surfaces)', () async {
      final fs = MemoryConfigFs()
        ..write('/c/config', 'a = 1\n')
        ..unreadable.add('/c/config');
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: ''),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(fs.replaced, isEmpty);
    });

    test('a no-op edit does not write', () async {
      final fs = MemoryConfigFs()..write('/c/config', 'a = 1\n');
      await ConfigFileWriter(fs).edit('/c/config', [
        RemoveBinding(c('ctrl+alt+n'), isDefault: false),
      ], template: '');
      expect(fs.replaced, isEmpty);
      final missing = MemoryConfigFs();
      await ConfigFileWriter(missing).edit('/c/config', [
        ResetAction(const KeyAction('new_tab'), const []),
      ], template: '# t\n');
      expect(missing.replaced, isEmpty);
      expect(missing.files, isEmpty);
    });

    test('a damaged block is refused and the file untouched', () async {
      final fs = MemoryConfigFs()..write('/c/config', '$kManagedStart\n');
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: ''),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(fs.replaced, isEmpty);
    });

    test('NUL bytes (UTF-16 without a BOM) are refused', () async {
      final fs = MemoryConfigFs()
        ..writeBytes('/c/config', [0x61, 0, 0x3D, 0, 0x31, 0, 0x0A, 0]);
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: ''),
        throwsA(
          isA<ConfigWriteRefused>().having(
            (e) => e.reason,
            'reason',
            ConfigWriteRefusal.notText,
          ),
        ),
      );
      expect(fs.replaced, isEmpty);
    });

    test('invalid UTF-8 is refused, not rewritten', () async {
      final fs = MemoryConfigFs()..writeBytes('/c/config', [0x61, 0xFF, 0x0A]);
      await expectLater(
        ConfigFileWriter(fs).edit('/c/config', add, template: ''),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(fs.replaced, isEmpty);
    });
  });

  group('editText (A11 D5: the settings\' key edits)', () {
    const path = '/c/config';
    String bump(String t) =>
        applyKeyEdits(t, [const SetKey('font-size', '15')]);

    test('keeps the BOM and the CRLFs, changes only the line', () async {
      final fs = MemoryConfigFs()
        ..writeBytes(path, [
          0xEF, 0xBB, 0xBF, //
          ...utf8.encode('# mine\r\nfont-size = 13\r\ntheme = X\r\n'),
        ]);
      await ConfigFileWriter(fs).editText(path, bump, template: '');
      expect(fs.files[path]!.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(
        utf8.decode(fs.files[path]!.sublist(3)),
        '# mine\r\nfont-size = 15\r\ntheme = X\r\n',
      );
    });

    test('UTF-16 files are refused and left alone', () async {
      final fs = MemoryConfigFs()
        ..writeBytes(path, [0xFF, 0xFE, 0x61, 0x00, 0x0A, 0x00]);
      await expectLater(
        ConfigFileWriter(fs).editText(path, bump, template: ''),
        throwsA(
          isA<ConfigWriteRefused>().having(
            (e) => e.reason,
            'reason',
            ConfigWriteRefusal.utf16,
          ),
        ),
      );
      expect(fs.replaced, isEmpty);
    });

    test('a file changed after the read is refused (expected bytes)', () async {
      final fs = MemoryConfigFs()..write(path, 'font-size = 13\n');
      fs.beforeReplace = (p) => fs.write(p, 'font-size = 99\n');
      await expectLater(
        ConfigFileWriter(fs).editText(path, bump, template: ''),
        throwsA(
          isA<ConfigWriteRefused>().having(
            (e) => e.reason,
            'reason',
            ConfigWriteRefusal.changed,
          ),
        ),
      );
      expect(fs.text(path), 'font-size = 99\n');
    });

    test('a missing file is made from the template, with the edit', () async {
      final fs = MemoryConfigFs();
      await ConfigFileWriter(fs).editText(path, bump, template: '# t\n');
      expect(fs.text(path), startsWith('# t\n'));
      expect(fs.text(path), contains('font-size = 15'));
    });

    test('a transform that changes nothing writes nothing', () async {
      final fs = MemoryConfigFs();
      await ConfigFileWriter(fs).editText(path, (t) => t, template: '# t\n');
      expect(fs.files, isEmpty);
      fs.write(path, 'a = 1\n');
      await ConfigFileWriter(fs).editText(
        path,
        (t) => applyKeyEdits(t, [const ResetKey('font-size')]),
        template: '',
      );
      expect(fs.replaced, isEmpty);
    });

    test('a damaged block surfaces as a refusal and the file stays', () async {
      final fs = MemoryConfigFs()..write(path, '$kSettingsStart\na = 1\n');
      await expectLater(
        ConfigFileWriter(fs).editText(path, bump, template: ''),
        throwsA(
          isA<ConfigWriteRefused>().having(
            (e) => e.reason,
            'reason',
            ConfigWriteRefusal.damagedBlock,
          ),
        ),
      );
      expect(fs.replaced, isEmpty);
    });

    test('a result over the size limit is refused', () async {
      final fs = MemoryConfigFs()..write(path, '# x\n');
      await expectLater(
        ConfigFileWriter(fs).editText(
          path,
          (t) => '$t${'#' * (kConfigMaxBytes + 1)}',
          template: '',
        ),
        throwsA(isA<ConfigWriteRefused>()),
      );
    });

    test('edit still goes through editText (same refusals)', () async {
      final fs = MemoryConfigFs()..write(path, 'a = 1\n$kManagedStart\n');
      await expectLater(
        ConfigFileWriter(fs).edit(path, [
          AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab')),
        ], template: ''),
        throwsA(isA<ConfigWriteRefused>()),
      );
    });

    test(
      'real file: mode and symlink kept, no temporary file left',
      () async {
        final dir = Directory.systemTemp.createTempSync('shellx-keyedit-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/config')
          ..writeAsBytesSync([
            0xEF,
            0xBB,
            0xBF,
            ...utf8.encode('font-size = 13\r\n'),
          ]);
        Process.runSync('chmod', ['600', file.path]);
        await ConfigFileWriter(
          const IoConfigFileStore(),
        ).editText(file.path, bump, template: '');
        expect(file.statSync().mode & 0xFFF, 384);
        expect(file.readAsBytesSync().sublist(0, 3), [0xEF, 0xBB, 0xBF]);
        expect(
          utf8.decode(file.readAsBytesSync().sublist(3)),
          'font-size = 15\r\n',
        );
        expect(dir.listSync(), hasLength(1));
      },
      skip: Platform.isWindows,
    );
  });

  group('IoConfigFileStore (real files)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('shellx-writer-'));
    tearDown(() => dir.deleteSync(recursive: true));

    final add = [AddBinding(c('ctrl+alt+n'), const KeyAction('new_tab'))];
    final writer = ConfigFileWriter(const IoConfigFileStore());

    List<String> names(Directory d) => [
      for (final e in d.listSync())
        e.uri.pathSegments.where((s) => s.isNotEmpty).last,
    ]..sort();

    test(
      'writes through a symlink: the link stays, the target changes',
      () async {
        final dotfiles = Directory('${dir.path}/dotfiles')..createSync();
        final target = File('${dotfiles.path}/shellx')
          ..writeAsStringSync('# mine\r\nfont-size = 14\r\n');
        final link = Link('${dir.path}/config')..createSync(target.path);
        await writer.edit(link.path, add, template: '');
        expect(FileSystemEntity.isLinkSync(link.path), isTrue);
        expect(link.targetSync(), target.path);
        expect(
          target.readAsStringSync(),
          '# mine\r\nfont-size = 14\r\n$kManagedStart\r\nkeybind = ctrl+alt+n=new_tab\r\n$kManagedEnd\r\n',
        );
        // The temporary file lived next to the real target and is gone.
        expect(names(dotfiles), ['shellx']);
        expect(names(dir), ['config', 'dotfiles']);
      },
      skip: Platform.isWindows,
    );

    test('a dangling symlink is created at its target', () async {
      final target = '${dir.path}/dotfiles/shellx';
      final link = Link('${dir.path}/config')..createSync(target);
      await writer.edit(link.path, add, template: '# t\n');
      expect(FileSystemEntity.isLinkSync(link.path), isTrue);
      expect(
        File(target).readAsStringSync(),
        startsWith('# t\n$kManagedStart'),
      );
    }, skip: Platform.isWindows);

    test('keeps the file permissions', () async {
      final file = File('${dir.path}/config')..writeAsStringSync('a = 1\n');
      Process.runSync('chmod', ['600', file.path]);
      await writer.edit(file.path, add, template: '');
      expect(file.statSync().mode & 0xFFF, 384); // 0600
      expect(file.readAsStringSync(), contains('ctrl+alt+n=new_tab'));
      expect(names(dir), ['config']);
    }, skip: Platform.isWindows);

    test(
      'a read-only file (0444) is still replaced, mode kept',
      () async {
        final file = File('${dir.path}/config')..writeAsStringSync('a = 1\n');
        Process.runSync('chmod', ['444', file.path]);
        await writer.edit(file.path, add, template: '');
        expect(file.statSync().mode & 0xFFF, 292); // 0444
        expect(file.readAsStringSync(), contains('ctrl+alt+n=new_tab'));
        expect(names(dir), ['config']);
      },
      skip: Platform.isWindows,
    );

    test('a new file is 0600, whatever the umask', () async {
      final file = File('${dir.path}/new/config');
      await writer.edit(file.path, add, template: '# t\n');
      expect(file.statSync().mode & 0xFFF, 384); // 0600
      expect(names(Directory('${dir.path}/new')), ['config']);
    }, skip: Platform.isWindows);

    test('creates the folder and the file when missing', () async {
      final path = '${dir.path}/a/b/config';
      await writer.edit(path, add, template: '# t\n');
      expect(File(path).readAsStringSync(), startsWith('# t\n$kManagedStart'));
    });

    test('a change between the read and the rename is refused', () async {
      final file = File('${dir.path}/config')..writeAsStringSync('a = 1\n');
      const store = IoConfigFileStore();
      final read = (await store.read(file.path))!;
      file.writeAsStringSync('a = 2\n');
      await expectLater(
        store.replace(
          file.path,
          Uint8List.fromList(utf8.encode('x\n')),
          expected: read,
        ),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(file.readAsStringSync(), 'a = 2\n');
      expect(names(dir), ['config']); // no temp file left behind
    });

    test(
      'a file created between the read and the rename is not replaced',
      () async {
        final path = '${dir.path}/config';
        final store = IoConfigFileStore(
          beforeSwap: () async => File(path).writeAsStringSync('theirs = 1\n'),
        );
        await expectLater(
          store.replace(
            path,
            Uint8List.fromList(utf8.encode('x\n')),
            mustNotExist: true,
          ),
          throwsA(
            isA<ConfigWriteRefused>().having(
              (e) => e.reason,
              'reason',
              ConfigWriteRefusal.changed,
            ),
          ),
        );
        expect(File(path).readAsStringSync(), 'theirs = 1\n');
        expect(names(dir), ['config']); // no temp file left behind
      },
    );

    test('an existing file is not created over', () async {
      final file = File('${dir.path}/config')..writeAsStringSync('a = 1\n');
      await expectLater(
        const IoConfigFileStore().replace(
          file.path,
          Uint8List.fromList(utf8.encode('x\n')),
          mustNotExist: true,
        ),
        throwsA(isA<ConfigWriteRefused>()),
      );
      expect(file.readAsStringSync(), 'a = 1\n');
    });
  });
}
