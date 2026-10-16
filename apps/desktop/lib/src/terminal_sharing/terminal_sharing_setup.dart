import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;

import 'config_file_editor.dart';
import 'powershell.dart';
import 'sharing_paths.dart';
import 'shell_blocks.dart';
import 'term_binary.dart';

/// What turning sharing on will do; shown in the confirmation (spec §10.1).
final class SharingPlan {
  const SharingPlan({
    required this.files,
    required this.bashSkipped,
    required this.powerShells,
  });

  /// Startup files that get the block, in order.
  final List<PlannedFile> files;

  /// macOS: neither `~/.bashrc` nor `~/.bash_profile` exists, so bash is
  /// left alone.
  final bool bashSkipped;

  /// Windows: every PowerShell found, with its script policy.
  final List<PowerShellInstall> powerShells;
}

final class PlannedFile {
  const PlannedFile(this.target, {required this.exists});

  final ConfigTarget target;

  /// False: the file will be created.
  final bool exists;

  String get path => target.path;
}

/// Turning sharing on failed at [path] (the `bin` copy or a startup file);
/// everything done before was undone.
final class SharingSetupException implements Exception {
  const SharingSetupException(this.path, this.cause);
  final String path;
  final Object cause;
  @override
  String toString() => 'SharingSetupException($path): ${cause.runtimeType}';
}

/// An enable that worked, and how to take it back (the server failed to
/// start afterwards, spec §10.1 step 3).
final class SharingInstall {
  SharingInstall(this._undo, {this.editedFiles = const []});
  final Future<void> Function() _undo;

  /// Startup files this enable changed or created (remembered so disable
  /// cleans them even if PowerShell no longer reports them).
  final List<String> editedFiles;
  Future<void> undo() => _undo();
}

/// What [TerminalSharingSetup.disable] could not finish.
final class DisableResult {
  const DisableResult({required this.failedFiles, required this.binRemoved});

  /// Startup files whose block could not be removed.
  final List<String> failedFiles;

  /// False on Windows while a terminal still runs `shellx-term.exe`: the
  /// next start finishes the job.
  final bool binRemoved;

  bool get complete => failedFiles.isEmpty && binRemoved;
}

/// Installs, checks and removes terminal sharing's files (spec §10): the
/// `shellx-term` copy in `bin` and the blocks in the shell startup files.
/// Starting and stopping the local server is the runtime's job
/// (`AgentRuntime.setTerminalSharing`).
///
/// Changes startup files only from [enable], [disable] and [cleanup], that
/// is, only when the user turns the switch on or off (spec §10.2).
class TerminalSharingSetup {
  TerminalSharingSetup({
    required this.paths,
    TermBinaryInstaller? binary,
    ConfigFileEditor editor = const ConfigFileEditor(),
    PowerShellProbe? powerShell,
  }) : binary = binary ?? TermBinaryInstaller(paths),
       _editor = editor,
       _powerShell = powerShell;

  final SharingPaths paths;
  final TermBinaryInstaller binary;
  final ConfigFileEditor _editor;
  final PowerShellProbe? _powerShell;

  bool get windows => paths.windows;

  String _home(String name) => p.join(paths.home, name);

  /// The files [enable] would edit or create, as they are now.
  Future<SharingPlan> prepare() async {
    if (windows) {
      final shells = await _powerShells();
      return SharingPlan(
        files: [
          for (final shell in shells)
            if (shell.policy != ScriptPolicy.blockedByGroupPolicy)
              await _planned(
                ConfigTarget(
                  path: shell.profilePath,
                  block: powerShellBlock,
                  create: true,
                  newFileEol: '\r\n',
                ),
              ),
        ],
        bashSkipped: false,
        powerShells: shells,
      );
    }
    final files = [
      await _planned(
        ConfigTarget(
          path: _home('.zshrc'),
          block: zshBlock,
          create: true,
          newFileEol: '\n',
        ),
      ),
    ];
    // Spec §5.2 / §10.2: both bash files when they exist (a block in
    // `.bashrc` alone misses login windows); never create either.
    for (final name in ['.bash_profile', '.bashrc']) {
      final path = _home(name);
      // File.exists follows links: a dangling symlink counts as missing.
      if (await File(path).exists()) {
        files.add(
          PlannedFile(
            ConfigTarget(
              path: path,
              block: bashBlock,
              create: false,
              newFileEol: '\n',
            ),
            exists: true,
          ),
        );
      }
    }
    return SharingPlan(
      files: files,
      bashSkipped: files.length == 1,
      powerShells: const [],
    );
  }

  /// Spec §10.1 steps 1–3: copies `shellx-term` into `bin` (before any
  /// block: a block needs a binary with `probe`), backs each file up once,
  /// inserts the blocks. A failure undoes the steps done so far and
  /// rethrows.
  /// Failures are a [SharingSetupException] naming the file.
  Future<SharingInstall> enable(SharingPlan plan) async {
    final binExisted = await Directory(paths.binDir).exists();
    try {
      await binary.install();
    } catch (error) {
      if (!binExisted) await _quietly(binary.remove, 'removing bin');
      throw SharingSetupException(paths.binary, error);
    }
    final edits = <ConfigEdit>[];
    Future<void> undo() async {
      for (final edit in edits.reversed) {
        await _quietly(edit.undo, 'restoring a startup file');
      }
      if (!binExisted) await _quietly(binary.remove, 'removing bin');
    }

    for (final file in plan.files) {
      try {
        edits.add(await _editor.install(file.target));
      } catch (error) {
        await undo();
        throw SharingSetupException(file.path, error);
      }
    }
    return SharingInstall(
      undo,
      editedFiles: [
        for (final edit in edits)
          if (edit.changed) edit.path,
      ],
    );
  }

  /// Spec §10.5: removes the block from every startup file that may have
  /// one, calls [stopServer] (closes the port, deletes `endpoint`), then
  /// deletes `bin`. Never throws; reports what it could not do.
  ///
  /// [knownFiles]: files an earlier enable edited (stored by the caller);
  /// cleaned together with the ones found now. A file that still has a
  /// block afterwards is reported in [DisableResult.failedFiles].
  Future<DisableResult> disable({
    Future<void> Function()? stopServer,
    List<String> knownFiles = const [],
  }) async {
    final failed = <String>[];
    final files = {...knownFiles, ...await _allStartupFiles()};
    for (final path in files) {
      try {
        await _editor.remove(path);
        if (await _editor.installedBlock(path) != null) failed.add(path);
      } catch (error) {
        debugPrint('ShellX: removing a block failed: ${error.runtimeType}');
        failed.add(path);
      }
    }
    if (stopServer != null) {
      await _quietly(stopServer, 'stopping terminal sharing');
    }
    var binRemoved = false;
    try {
      binRemoved = await binary.remove();
    } catch (error) {
      debugPrint('ShellX: removing bin failed: ${error.runtimeType}');
    }
    return DisableResult(failedFiles: failed, binRemoved: binRemoved);
  }

  /// Spec §7.6: true when the switch is on but a block is missing or out of
  /// date in a startup file that should have one, or `shellx-term` is
  /// missing from `bin`.
  Future<bool> needsSetup() async {
    try {
      if (!await binary.installedExists()) return true;
      final plan = await prepare();
      for (final file in plan.files) {
        if (await _editor.installedBlock(file.path) != file.target.block) {
          return true;
        }
      }
      return false;
    } catch (error) {
      debugPrint(
        'ShellX: checking terminal sharing failed: ${error.runtimeType}',
      );
      return false;
    }
  }

  /// At every start (spec §10.4, §10.5). On: a `shellx-term` in `bin` that
  /// differs from the app's is replaced (a missing one is left for "set up
  /// again"); Windows deletes old copies nothing runs any more. Off: a
  /// `bin` left behind (a Windows binary still running at the last
  /// disable) is removed. Never throws.
  Future<void> maintain({required bool enabled}) async {
    if (enabled) {
      await _quietly(() async {
        if (await binary.installedExists() &&
            await binary.bundledExists() &&
            !await binary.isCurrent()) {
          await binary.install();
        }
        if (windows) await binary.cleanupOld();
      }, 'updating shellx-term');
    } else if (await Directory(paths.binDir).exists()) {
      await _quietly(binary.remove, 'removing bin');
    }
  }

  /// `ShellX.exe --terminal-sharing-cleanup` (Windows uninstaller, spec
  /// §10.6): blocks, `bin` and `term` go.
  Future<DisableResult> cleanup({List<String> knownFiles = const []}) async {
    final result = await disable(knownFiles: knownFiles);
    await _quietly(() async {
      final term = Directory(paths.termDir);
      if (await term.exists()) await term.delete(recursive: true);
    }, 'removing term');
    return result;
  }

  /// Windows: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` in
  /// [install], only after the user pressed the button (spec §10.3).
  Future<bool> allowLocalScripts(PowerShellInstall install) async =>
      await _powerShell?.allowLocalScripts(install) ?? false;

  Future<List<String>> _allStartupFiles() async {
    if (windows) {
      return [for (final shell in await _powerShells()) shell.profilePath];
    }
    return [_home('.zshrc'), _home('.bash_profile'), _home('.bashrc')];
  }

  Future<List<PowerShellInstall>> _powerShells() async =>
      await _powerShell?.find() ?? const [];

  static Future<PlannedFile> _planned(ConfigTarget target) async =>
      PlannedFile(target, exists: await File(target.path).exists());

  static Future<void> _quietly(
    Future<void> Function() action,
    String what,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('ShellX: $what failed: ${error.runtimeType}');
    }
  }
}
