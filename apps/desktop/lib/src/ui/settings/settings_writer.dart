import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config_controller.dart';
import '../../config/config_key_edits.dart';
import '../../config/config_problem.dart';
import '../../config/config_syntax.dart';
import '../../config/config_template.dart';
import '../../config/config_writer.dart';
import '../../config/setting_validation.dart';
import '../../config/settings_schema.dart';
import '../../config/shellx_config.dart';

/// What a Settings write came to (A11 D5, D6).
sealed class SettingsWrite {
  const SettingsWrite();
}

/// Written; the configuration was reloaded.
final class Saved extends SettingsWrite {
  const Saved();
}

/// The value is not valid (the loader's own verdict); nothing was written.
final class Invalid extends SettingsWrite {
  const Invalid(this.problem);
  final ConfigProblem problem;

  @override
  String toString() => '…';
}

/// The write was refused (damaged block, unreadable or locked file …); the
/// file is as it was.
final class Refused extends SettingsWrite {
  const Refused(this.why);
  final ConfigWriteRefusal why;
}

/// The file changed while Settings was open: nothing was written, the new
/// content was loaded.
final class Changed extends SettingsWrite {
  const Changed();
}

/// A write that would add an error to the file: the line is not written.
final class _WouldBreak implements Exception {
  const _WouldBreak(this.problem);
  final ConfigProblem problem;
}

final settingsWriterProvider = Provider<SettingsWriter>(SettingsWriter.new);

/// The only place the Settings window writes the configuration file. One
/// write at a time; every one re-reads the file first (`editText`) and keeps
/// every byte outside the edited line.
class SettingsWriter {
  SettingsWriter(this._ref);
  final Ref _ref;

  Future<void> _tail = Future.value();

  bool get _mac => _ref.read(configPlatformProvider) == TargetPlatform.macOS;

  Future<SettingsWrite> set(SettingDef def, String raw) async {
    final key = def.fileKey!;
    final paths = _ref.read(configPathsProvider);
    final check = validateSetting(
      key,
      raw,
      macos: _mac,
      home: paths.home,
      windows: paths.windows,
    );
    if (!check.ok) return Invalid(check.problem!);
    return _write((t) => applyKeyEdits(t, [SetKey(key, raw.trim())]));
  }

  Future<SettingsWrite> reset(SettingDef def) {
    final paths = _ref.read(configPathsProvider);
    final src = settingSource(def, _ref.read(shellxConfigProvider), paths);
    return _write(
      (t) => applyKeyEdits(t, [
        ResetKey(def.fileKey!, explicitDefault: src is GhosttySource),
      ]),
    );
  }

  Future<SettingsWrite> resetAll() => write(removeSettingsBlock);

  /// Runs [edit] on the file's text under the one-write-at-a-time rule and
  /// the loader check. The public ways in are [set], [reset], [resetAll].
  @visibleForTesting
  Future<SettingsWrite> write(String Function(String) edit) => _write(edit);

  Future<SettingsWrite> _write(String Function(String) edit) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => _run(edit)).whenComplete(done.complete);
  }

  Future<SettingsWrite> _run(String Function(String) edit) async {
    final paths = _ref.read(configPathsProvider);
    try {
      await _ref
          .read(configFileWriterProvider)
          .editText(
            paths.shellx,
            (text) => _guard(text, edit(text)),
            template: shellxTemplate(_ref.read),
          );
    } on _WouldBreak catch (e) {
      return Invalid(e.problem);
    } on ConfigWriteRefused catch (e) {
      if (e.reason == ConfigWriteRefusal.changed) {
        await _ref.read(shellxConfigProvider.notifier).load();
        return const Changed();
      }
      return Refused(e.reason);
    } on Object catch (e) {
      // A locked or read-only file, a full disk: only what went wrong.
      debugPrint('ShellX: setting not saved: ${e.runtimeType}');
      return const Refused(ConfigWriteRefusal.unreadable);
    }
    await _ref.read(shellxConfigProvider.notifier).load(ownWrite: true);
    return const Saved();
  }

  /// What the real loader says about [text] as the ShellX file.
  List<ConfigProblem> _problemsOf(String text) {
    final paths = _ref.read(configPathsProvider);
    final problems = <ConfigProblem>[];
    final entries = parseConfigText(
      text,
      file: paths.shellx,
      problems: problems,
    );
    buildShellxConfig(
      ghostty: const [],
      shellx: entries,
      problems: problems,
      macos: _mac,
      home: paths.home,
      windows: paths.windows,
    );
    return problems;
  }

  /// D6: the whole would-be text goes through the real loader; an error the
  /// file did not have before is not written.
  String _guard(String before, String after) {
    if (after == before) return after;
    final known = {
      for (final p in _problemsOf(before))
        if (p.severity == ConfigSeverity.error) (p.code, p.key),
    };
    for (final p in _problemsOf(after)) {
      if (p.severity == ConfigSeverity.error &&
          !known.contains((p.code, p.key))) {
        throw _WouldBreak(p);
      }
    }
    return after;
  }
}
