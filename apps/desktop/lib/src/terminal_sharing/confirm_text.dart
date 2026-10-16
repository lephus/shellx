import '../../l10n/app_localizations.dart';
import 'powershell.dart';
import 'terminal_sharing_setup.dart';

/// The confirmation shown before turning terminal sharing on (spec §10.1):
/// the limits, the exact files changed or created, the binary copy, and
/// the platform notes (macOS: R2, Terminal.app stops asking before closing
/// a busy window; Windows: the script policy of each PowerShell).
String sharingConfirmBody(
  SharingPlan plan,
  AppLocalizations l10n, {
  required bool windows,
  required String binaryPath,
}) {
  final out = StringBuffer()
    ..writeln(l10n.confirmSharingIntro)
    ..writeln();
  if (plan.files.isNotEmpty) {
    out.writeln(l10n.confirmSharingFiles);
    for (final file in plan.files) {
      out.writeln(
        '• ${file.exists ? file.path : l10n.confirmSharingFileCreated(file.path)}',
      );
    }
  }
  out.writeln(l10n.confirmSharingBinary(binaryPath));
  if (plan.bashSkipped) {
    out
      ..writeln()
      ..writeln(l10n.confirmSharingBashSkipped);
  }
  if (windows) {
    out.writeln();
    if (plan.powerShells.isEmpty) out.writeln(l10n.confirmSharingNoPowerShell);
    for (final shell in plan.powerShells) {
      switch (shell.policy) {
        case ScriptPolicy.allowed:
          break;
        case ScriptPolicy.blocked:
          out.writeln(l10n.confirmSharingPowerShellBlocked(shell.name));
        case ScriptPolicy.blockedByGroupPolicy:
          out.writeln(l10n.confirmSharingPowerShellGroupPolicy(shell.name));
      }
    }
    out.writeln(l10n.confirmSharingWindowsNote);
  } else {
    out
      ..writeln()
      ..writeln(l10n.confirmSharingMacNote);
  }
  return out.toString().trimRight();
}

/// PowerShells whose script policy the user can change for their account.
List<PowerShellInstall> fixablePowerShells(SharingPlan plan) => [
  for (final shell in plan.powerShells)
    if (shell.policy == ScriptPolicy.blocked) shell,
];
