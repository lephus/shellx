import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/l10n.dart';

/// "Are you sure?" with Cancel and [confirmLabel]; true only when confirmed.
Future<bool> showConfirmDialog(BuildContext context, {required String message, required String confirmLabel}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message, style: context.typo.subHeader),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(S.of(context).actionCancel)),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}
