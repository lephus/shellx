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

  /// A PowerShell profile: the block goes after a leading `using …` /
  /// `param(…)` prelude, which must stay first (spec §10.2).
  bool get powerShell => path.toLowerCase().endsWith('.ps1');
}

/// A startup file that cannot be edited, named for the user.
final class ConfigFileException implements Exception {
  const ConfigFileException(this.path, this.reason);
  final String path;
  final String reason;
  @override
  String toString() => 'ConfigFileException: $path $reason';
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
      try {
        await file.writeAsBytes(
          encodeConfig(ConfigText(text, ConfigEncoding.ascii8, null)),
          flush: true,
        );
      } catch (_) {
        await _quietly(() async {
          if (await file.exists()) await file.delete();
        });
        rethrow;
      }
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
      powerShell: target.powerShell,
    );
    if (text == config.text) {
      return ConfigEdit._(path: target.path, changed: false);
    }
    final backup = File(backupPath(target.path));
    var madeBackup = false;
    var wrote = false;
    try {
      if (!await backup.exists()) {
        madeBackup = true;
        await _writeWithModeOf(backup, original, file);
      }
      wrote = true;
      await file.writeAsBytes(encodeConfig(config.withText(text)), flush: true);
    } catch (_) {
      // Leave nothing behind: the file as it was (if the write may have
      // started), and no backup made by this call.
      if (wrote) {
        await _quietly(() => file.writeAsBytes(original, flush: true));
      }
      if (madeBackup) {
        await _quietly(() async {
          if (await backup.exists()) await backup.delete();
        });
      }
      rethrow;
    }
    return ConfigEdit._(
      path: target.path,
      changed: true,
      undo: () async {
        await file.writeAsBytes(original, flush: true);
        if (madeBackup && await backup.exists()) await backup.delete();
      },
    );
  }

  /// Writes [bytes] to a new [target] that has the permissions of [like]
  /// (a 0600 rc file keeps a 0600 backup), set before any byte is written.
  static Future<void> _writeWithModeOf(
    File target,
    List<int> bytes,
    File like,
  ) async {
    if (!Platform.isWindows) {
      final mode = (await like.stat()).mode & 0x1FF;
      await target.writeAsBytes(const [], flush: true);
      final result = await Process.run('/bin/chmod', [
        mode.toRadixString(8),
        target.path,
      ]);
      if (result.exitCode != 0) {
        throw FileSystemException('chmod failed', target.path);
      }
    }
    await target.writeAsBytes(bytes, flush: true);
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Best effort while already failing.
    }
  }

  /// Removes every ShellX block from [path]. False when the file is missing
  /// or had none.
  Future<bool> remove(String path) async {
    if (await FileSystemEntity.isLink(path) && !await File(path).exists()) {
      return false; // Dangling: nothing of ours to remove.
    }
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
    } on ConfigFileException {
      return null;
    }
  }

  static String? installedBlockIn(Uint8List bytes) =>
      config_text.installedBlock(decodeConfig(bytes).text);

  /// A symlink resolves to its target; a dangling one is refused with a
  /// [ConfigFileException] naming [path] (writing through it would create a
  /// file somewhere the user did not expect).
  static Future<File> _resolve(String path) async {
    if (await FileSystemEntity.isLink(path)) {
      if (!await File(path).exists()) {
        throw ConfigFileException(path, 'points to a file that does not exist');
      }
      return File(await File(path).resolveSymbolicLinks());
    }
    return File(path);
  }
}
