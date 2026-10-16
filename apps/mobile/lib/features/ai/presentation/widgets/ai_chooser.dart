import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_new_session_sheet.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/session_picker.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b B21, B22: the computer's AI sessions to pick from — the session picker's AI group alone, with
/// "Phiên AI mới" when the computer can start one (V2-2 D9) — from [listing]. The session picked, or the
/// new one, opens over this page, or in its place with [replace] (a closed session's page, B22). A new
/// session that may or may not have been made says so, as the terminal page does: nothing is asked again
/// by itself (V2-2 D13).
Future<void> openAiChooser(
  BuildContext context, {
  required String agentId,
  required String machineName,
  required AiMachine ai,
  required AiListing listing,
  bool replace = false,
}) async {
  final choice = await showSessionPicker(
    context,
    SessionListing(const [], desktopSharing: null, aiSupported: true, ai: listing),
    aiOnly: true,
  );
  if (!context.mounted) return;
  final String sid;
  switch (choice) {
    case OpenAiSession(:final session):
      sid = session.sid;
    case NewAiSession():
      final picked = await showAiNewSessionSheet(context, listing);
      if (picked == null || !context.mounted) return;
      String? made;
      String? code;
      try {
        made = await ai.open(picked.agent, picked.folder);
      } on AiRequestException catch (e) {
        code = e.code;
      } on MachineConnectionException catch (e) {
        code = switch (e.failure) {
          MachineConnectionFailure.agentOffline || MachineConnectionFailure.timeout => AiWords.openUnknown,
          MachineConnectionFailure.untrusted => AiWords.untrusted,
          MachineConnectionFailure.protocolUnsupported => AiWords.updateRequired,
        };
      }
      if (!context.mounted) return;
      if (made == null) {
        final text = AiWords.failure(S.of(context), code ?? 'refused');
        if (text != null) getIt<PopupHandler>().showError(title: text);
        return;
      }
      sid = made;
    case AttachSession() || OpenNewSession() || null:
      return;
  }
  // Keyed by its session: a page that takes the place of another session's page is a new page (the
  // router would otherwise keep the old one's state, and so its session).
  final route = AiSessionRoute(key: ValueKey('ai:$agentId/$sid'), agentId: agentId, machineName: machineName, sid: sid);
  // Each completes when the page closes: not awaited.
  unawaited(replace ? context.router.replace(route) : context.router.push(route));
}
