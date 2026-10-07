import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../config/config_problem.dart';

/// UI-A9 §7.2: the localized message of [problem] (en = the CLI's text).
/// Only what the problem carries (key names, values, hints) is shown, never
/// anything else from the files.
String problemText(AppLocalizations l10n, ConfigProblem problem) {
  final key = problem.key ?? '';
  final value = problem.value ?? '';
  final hint = problem.hint ?? '';
  final detail = problem.detail ?? '';
  return switch (problem.code) {
    ConfigProblemCode.syntax => l10n.configProblemSyntax,
    ConfigProblemCode.badKey => l10n.configProblemBadKey(key),
    ConfigProblemCode.unknownKey => l10n.configProblemUnknownKey(key),
    ConfigProblemCode.badValue => l10n.configProblemBadValue(key, value, hint),
    ConfigProblemCode.outOfRange => l10n.configProblemOutOfRange(
      key,
      value,
      hint,
      detail,
    ),
    ConfigProblemCode.duplicate => l10n.configProblemDuplicate(key, detail),
    ConfigProblemCode.includeMissing => l10n.configProblemIncludeMissing(value),
    ConfigProblemCode.includeCycle => l10n.configProblemIncludeCycle(value),
    ConfigProblemCode.includeDepth => l10n.configProblemIncludeDepth,
    ConfigProblemCode.includeLimit => l10n.configProblemIncludeLimit,
    ConfigProblemCode.unreadable => l10n.configProblemUnreadable,
    ConfigProblemCode.notUtf8 => l10n.configProblemNotUtf8,
    ConfigProblemCode.tooLarge => l10n.configProblemTooLarge,
    ConfigProblemCode.themeNotFound => l10n.configProblemThemeNotFound(value),
    ConfigProblemCode.fontNotFound => l10n.configProblemFontNotFound(value),
    ConfigProblemCode.fontNotMonospace => l10n.configProblemFontNotMonospace(
      value,
    ),
    ConfigProblemCode.lowContrast => l10n.configProblemLowContrast(detail),
    ConfigProblemCode.unsupportedValue => l10n.configProblemUnsupportedValue(
      key,
      value,
      hint,
    ),
    ConfigProblemCode.notOnThisPlatform => l10n.configProblemNotOnThisPlatform(
      key,
    ),
    ConfigProblemCode.badTrigger => l10n.configProblemBadTrigger(value),
    ConfigProblemCode.unknownAction => l10n.configProblemUnknownAction(value),
    ConfigProblemCode.badActionParam => l10n.configProblemBadActionParam(
      value,
      hint,
    ),
    ConfigProblemCode.reservedTrigger => l10n.configProblemReservedTrigger(
      value,
    ),
    ConfigProblemCode.plainKeyTrigger => l10n.configProblemPlainKeyTrigger(
      value,
    ),
    ConfigProblemCode.regionTrigger => l10n.configProblemRegionTrigger,
    ConfigProblemCode.shellKeyTrigger => l10n.configProblemShellKeyTrigger(
      value,
    ),
    ConfigProblemCode.optionKeyTrigger => l10n.configProblemOptionKeyTrigger(
      value,
    ),
    ConfigProblemCode.altGrTrigger => l10n.configProblemAltGrTrigger(value),
    ConfigProblemCode.missionControlTrigger =>
      l10n.configProblemMissionControlTrigger(value),
    ConfigProblemCode.unsupportedPrefix => l10n.configProblemUnsupportedPrefix(
      value,
    ),
    ConfigProblemCode.sequenceTooLong => l10n.configProblemSequenceTooLong,
    ConfigProblemCode.sequencePrefixShadows =>
      l10n.configProblemSequencePrefixShadows(value),
    ConfigProblemCode.sequenceRepeatsPrefix =>
      l10n.configProblemSequenceRepeatsPrefix(value),
    ConfigProblemCode.unknownCommand => l10n.configProblemUnknownCommand(value),
    ConfigProblemCode.commandLimit => l10n.configProblemCommandLimit,
    ConfigProblemCode.problemLimit => l10n.configProblemLimit(detail),
    ConfigProblemCode.internal => l10n.configProblemInternal,
  };
}

/// "config, line 3": the file's base name; line 0 is the whole file (the
/// name only). A problem with no file (an unusable home) has no path:
/// "line 3", or nothing at all for the whole configuration.
String problemLocation(AppLocalizations l10n, ConfigProblem problem) {
  final name = problem.file.isEmpty
      ? ''
      : p.basename(problem.file.replaceAll(r'\', '/'));
  if (name.isEmpty) {
    return problem.line == 0 ? '' : l10n.configProblemLine(problem.line);
  }
  return problem.line == 0 ? name : l10n.configProblemWhere(name, problem.line);
}

String severityText(AppLocalizations l10n, ConfigSeverity s) => switch (s) {
  ConfigSeverity.error => l10n.configSeverityError,
  ConfigSeverity.warning => l10n.configSeverityWarning,
  ConfigSeverity.info => l10n.configSeverityInfo,
};
