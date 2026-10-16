import 'package:flutter/foundation.dart';

/// A9 spec D8: how much a problem matters. Notes never raise a toast (D36).
enum ConfigSeverity { error, warning, info }

/// A9 spec D8 / UI-A9 §7.2: one message per code.
enum ConfigProblemCode {
  syntax,
  badKey,
  unknownKey,
  badValue,
  outOfRange,
  duplicate,
  includeMissing,
  includeCycle,
  includeDepth,
  includeLimit,
  unreadable,
  notUtf8,
  tooLarge,
  themeNotFound,
  fontNotFound,
  fontNotMonospace,
  lowContrast,
  unsupportedValue,
  notOnThisPlatform,
  badTrigger,
  unknownAction,
  badActionParam,
  reservedTrigger,
  plainKeyTrigger,
  regionTrigger,
  shellKeyTrigger,
  optionKeyTrigger,
  altGrTrigger,
  missionControlTrigger,
  unsupportedPrefix,
  sequenceTooLong,
  sequencePrefixShadows,
  sequenceRepeatsPrefix,
  unknownCommand,
  commandLimit,
  problemLimit,
  internal,
}

/// One problem in one file: where, how bad, what. [line] is 1-based; 0
/// means the whole file. [key], [value], [hint], [detail] fill the
/// message's placeholders (UI-A9 §7.2); [hint] is literal syntax and is
/// never translated.
@immutable
final class ConfigProblem {
  const ConfigProblem({
    required this.file,
    required this.line,
    required this.severity,
    required this.code,
    this.key,
    this.value,
    this.hint,
    this.detail,
  });

  final String file;
  final int line;
  final ConfigSeverity severity;
  final ConfigProblemCode code;
  final String? key;
  final String? value;
  final String? hint;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is ConfigProblem &&
      other.file == file &&
      other.line == line &&
      other.severity == severity &&
      other.code == code &&
      other.key == key &&
      other.value == value &&
      other.hint == hint &&
      other.detail == detail;

  @override
  int get hashCode =>
      Object.hash(file, line, severity, code, key, value, hint, detail);

  @override
  String toString() => 'ConfigProblem(${code.name} line $line)';
}

/// The English message (CLI output, A7 D11). Must equal the en ARB text
/// of the same code (checked by `config_problems_ui_test`, Task 10).
String configProblemEnglish(ConfigProblem p) {
  final key = p.key ?? '';
  final value = p.value ?? '';
  final hint = p.hint ?? '';
  final detail = p.detail ?? '';
  return switch (p.code) {
    ConfigProblemCode.syntax => 'Line has no “=” (expected key = value)',
    ConfigProblemCode.badKey => '“$key” is not a valid key name',
    ConfigProblemCode.unknownKey => 'ShellX has no key “$key”',
    ConfigProblemCode.badValue =>
      '$key: “$value” is not valid (expected $hint)',
    ConfigProblemCode.outOfRange =>
      '$key: $value is outside $hint, using $detail',
    ConfigProblemCode.duplicate => '$key: replaces line $detail',
    ConfigProblemCode.includeMissing => 'File “$value” not found',
    ConfigProblemCode.includeCycle =>
      '“$value” is already loaded (config-file loop)',
    ConfigProblemCode.includeDepth =>
      'config-file is nested more than 4 levels',
    ConfigProblemCode.includeLimit =>
      'More than 64 config files — the rest are ignored',
    ConfigProblemCode.unreadable =>
      "Can't read the file — keeping the previous configuration",
    ConfigProblemCode.notUtf8 =>
      "The file isn't UTF-8 — keeping the previous configuration",
    ConfigProblemCode.tooLarge =>
      'The file is larger than 256 KiB — keeping the previous configuration',
    ConfigProblemCode.themeNotFound => 'Theme “$value” not found',
    ConfigProblemCode.fontNotFound =>
      'Font “$value” not found — using JetBrains Mono',
    ConfigProblemCode.fontNotMonospace =>
      "Font “$value” isn't monospaced — columns may not line up",
    ConfigProblemCode.lowContrast =>
      'Low text/background contrast ($detail:1, aim for 4.5:1)',
    ConfigProblemCode.unsupportedValue =>
      "$key = $value isn't supported (using $hint)",
    ConfigProblemCode.notOnThisPlatform => '$key only has an effect on macOS',
    ConfigProblemCode.badTrigger => '“$value” is not a valid key combination',
    ConfigProblemCode.unknownAction => "There's no action “$value”",
    ConfigProblemCode.badActionParam =>
      '“$value” is not valid (expected $hint)',
    ConfigProblemCode.reservedTrigger => '$value is reserved by the system',
    ConfigProblemCode.plainKeyTrigger =>
      '$value is for typing — add Ctrl, Alt or ⌘',
    ConfigProblemCode.regionTrigger =>
      'F6 and Shift+F6 always move between regions',
    ConfigProblemCode.shellKeyTrigger =>
      '$value will no longer reach the shell',
    ConfigProblemCode.optionKeyTrigger =>
      '$value will no longer type its Option character',
    ConfigProblemCode.altGrTrigger =>
      '$value works with the left Alt only; AltGr still types characters',
    ConfigProblemCode.missionControlTrigger =>
      'Mission Control may take $value',
    ConfigProblemCode.unsupportedPrefix =>
      "The “$value” prefix isn't supported",
    ConfigProblemCode.sequenceTooLong => 'Key sequences have at most 2 steps',
    ConfigProblemCode.sequencePrefixShadows =>
      '$value starts a key sequence, so it no longer works on its own',
    ConfigProblemCode.sequenceRepeatsPrefix =>
      "This sequence can't fire: pressing $value twice sends it",
    ConfigProblemCode.unknownCommand => "There's no command “$value”",
    ConfigProblemCode.commandLimit =>
      'More than 200 commands — the rest are ignored',
    ConfigProblemCode.problemLimit =>
      '$detail problems — showing the first 100',
    ConfigProblemCode.internal =>
      'Unexpected error — keeping the previous configuration',
  };
}
