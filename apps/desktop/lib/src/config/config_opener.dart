import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../terminal/terminal_tabs.dart';
import 'config_controller.dart';
import 'config_template.dart';

typedef ProcessStarter =
    Future<void> Function(String executable, List<String> arguments);

Future<void> _detached(String exe, List<String> args) async {
  await Process.start(exe, args, mode: ProcessStartMode.detached);
}

/// D37: creates the file from the template when missing (only here: the
/// app never writes the file on its own), then opens it in the default
/// text editor (macOS `open -t`, Windows Notepad).
class ConfigFileOpener {
  ConfigFileOpener({required this.windows, ProcessStarter? start})
    : _start = start ?? _detached;

  final bool windows;
  final ProcessStarter _start;

  Future<bool> open(String path, {required String Function() template}) async {
    try {
      final file = File(path);
      if (!await file.exists()) await _create(file, template);
      if (windows) {
        await _start('notepad.exe', [path]);
      } else {
        await _start('/usr/bin/open', ['-t', path]);
      }
      return true;
    } catch (error) {
      // Never the path or the text: only what went wrong.
      debugPrint('ShellX: opening the config failed: ${error.runtimeType}');
      return false;
    }
  }

  /// Created without ever replacing a file: whoever loses a race (a second
  /// open, another process) finds the file there and keeps it. The template
  /// is built only now. POSIX: written whole to a unique temp file, then
  /// hard-linked into place (`ln` fails when the target exists), so nobody
  /// reads a half-written config. Windows: exclusive create, then write.
  Future<void> _create(File file, String Function() template) async {
    await file.parent.create(recursive: true);
    if (windows) {
      try {
        await file.create(exclusive: true);
      } on FileSystemException {
        if (await file.exists()) return;
        rethrow;
      }
      try {
        await file.writeAsString(template(), flush: true);
      } catch (_) {
        if (await file.exists()) await file.delete();
        rethrow;
      }
      return;
    }
    final tmp = await file.parent.createTemp('.config-');
    try {
      final staged = File('${tmp.path}/new');
      await staged.writeAsString(template(), flush: true);
      final linked = await Process.run('/bin/ln', [staged.path, file.path]);
      if (linked.exitCode != 0 && !await file.exists()) {
        throw FileSystemException('link failed', file.path);
      }
    } finally {
      await tmp.delete(recursive: true);
    }
  }
}

final configFileOpenerProvider = Provider<ConfigFileOpener>(
  (ref) => ConfigFileOpener(windows: Platform.isWindows),
);

/// ⌘,, the palette, the tray, the problems panel (D37). Shows
/// [ConfigOpenFailedNotice] on failure. Takes `ref.read` so both a
/// `WidgetRef` (window) and a `Ref` (tray) can call it.
Future<bool> openShellxConfig(
  T Function<T>(ProviderListenable<T> provider) read,
) async {
  final path = read(configPathsProvider).shellx;
  final ok = await read(
    configFileOpenerProvider,
  ).open(path, template: () => shellxTemplate(read));
  if (!ok) {
    read(
      terminalTabsProvider.notifier,
    ).showNotice(ConfigOpenFailedNotice(path));
  }
  return ok;
}
