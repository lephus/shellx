import 'dart:io';
import 'dart:typed_data';

import 'config_text.dart';
import 'config_text.dart' as config_text show installedBlock;

/// A startup file that gets a ShellX block (spec §10.2).
final class ConfigTarget {
  const ConfigTarget({
    required this.path,
    required this.block,
    required this.create,
    required this.newFileEol,
  });

  final String path;

  /// LF, ending with a newline (`shell_blocks.dart`).
  final String block;

  /// Create the file when it does not exist (`~/.zshrc`, PowerShell
  /// profiles). False: a missing file is left missing (`~/.bash_profile`
  /// must never be created: bash would stop reading `~/.profile`).
  final bool create;

  /// Line ending of a file this editor creates.
  final String newFileEol;
}

/// What one [ConfigFileEditor.install] did, and how to take it back.
final class ConfigEdit {
  ConfigEdit._({
    required this.path,
    required this.changed,
    Future<void> Function()? undo,
  }) : _undo = undo;

  final String path;

  /// False when the file already had this block, or was missing and not
  /// to be created.
  final bool changed;
  final Future<void> Function()? _undo;

  /// Restores the file (deletes it if it was created) and removes the
  /// backup this edit made.
  Future<void> undo() async => _undo?.call();
}

/// Inserts and removes ShellX blocks, keeping each file's content, encoding
/// and line endings (spec §10.2). A symlinked file (dotfiles repos) is
/// edited in place through the link, so the link stays a link.
class ConfigFileEditor {
  const ConfigFileEditor();

  static String backupPath(String path) => '$path.shellx-backup';

  Future<ConfigEdit> install(ConfigTarget target) async {
    final file = await _resolve(target.path);
    if (!await file.exists()) {
      if (!target.create) {
        return ConfigEdit._(path: target.path, changed: false);
      }
      await file.parent.create(recursive: true);
      final text = insertBlock('', target.block, eol: target.newFileEol);
      await file.writeAsBytes(
        encodeConfig(ConfigText(text, ConfigEncoding.ascii8, null)),
        flush: true,
      );
      return ConfigEdit._(
        path: target.path,
        changed: true,
        undo: () async {
          if (await file.exists()) await file.delete();
        },
      );
    }
    final original = await file.readAsBytes();
    final config = decodeConfig(original);
    final text = insertBlock(
      config.text,
      target.block,
      eol: config.eol ?? target.newFileEol,
    );
    if (text == config.text) {
      return ConfigEdit._(path: target.path, changed: false);
    }
    final backup = File(backupPath(target.path));
    var madeBackup = false;
    if (!await backup.exists()) {
      await backup.writeAsBytes(original, flush: true);
      madeBackup = true;
    }
    await file.writeAsBytes(encodeConfig(config.withText(text)), flush: true);
    return ConfigEdit._(
      path: target.path,
      changed: true,
      undo: () async {
        await file.writeAsBytes(original, flush: true);
        if (madeBackup && await backup.exists()) await backup.delete();
      },
    );
  }

  /// Removes every ShellX block from [path]. False when the file is missing
  /// or had none.
  Future<bool> remove(String path) async {
    final file = await _resolve(path);
    if (!await file.exists()) return false;
    final config = decodeConfig(await file.readAsBytes());
    final text = removeBlock(config.text);
    if (text == config.text) return false;
    await file.writeAsBytes(encodeConfig(config.withText(text)), flush: true);
    return true;
  }

  /// The block in [path] (LF), or null when the file or the block is
  /// missing. An unreadable file counts as having no block.
  Future<String?> installedBlock(String path) async {
    try {
      final file = await _resolve(path);
      if (!await file.exists()) return null;
      return installedBlockIn(await file.readAsBytes());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static String? installedBlockIn(Uint8List bytes) =>
      config_text.installedBlock(decodeConfig(bytes).text);

  static Future<File> _resolve(String path) async {
    if (await FileSystemEntity.isLink(path)) {
      return File(await File(path).resolveSymbolicLinks());
    }
    return File(path);
  }
}
