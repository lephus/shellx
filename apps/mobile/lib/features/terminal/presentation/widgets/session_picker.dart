import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/shared/shared.dart';

sealed class SessionChoice {
  const SessionChoice();
}

final class AttachSession extends SessionChoice {
  const AttachSession(this.session);
  final SessionInfo session;
}

final class OpenNewSession extends SessionChoice {
  const OpenNewSession();
}

/// Spec §9.2 #4 / design "Chọn phiên có sẵn": the bottom sheet shown on the first visit of a
/// machine that already runs sessions. Returns null when dismissed.
Future<SessionChoice?> showSessionPicker(BuildContext context, List<SessionInfo> sessions, {DateTime? now}) {
  return showModalBottomSheet<SessionChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) {
      final strings = S.of(context);
      final colors = context.colors;
      final at = now ?? DateTime.now();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.pickerTitle(sessions.length), style: context.typo.heading20.heavy),
              6.sizedHeight,
              Text(strings.pickerSubtitle, style: context.typo.subHeader15.copyWith(color: colors.secondaryText)),
              14.sizedHeight,
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, session) in sessions.indexed) ...[
                      if (i > 0) Divider(height: 1, color: colors.divider),
                      InkWell(
                        onTap: () => Navigator.pop(context, AttachSession(session)),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${session.shell} ${session.index}',
                                        style: TextStyle(
                                          fontFamily: FontFamily.jetBrainsMono,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                          color: colors.primaryText,
                                        ),
                                      ),
                                      2.sizedHeight,
                                      Text(
                                        [
                                          strings.pickerStarted(
                                            formatLastSeen(
                                              strings,
                                              DateTime.fromMillisecondsSinceEpoch(session.createdAt),
                                              at,
                                            ),
                                          ),
                                          if (session.attached) strings.pickerAttachedElsewhere,
                                        ].join(' · '),
                                        style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  strings.pickerOpen,
                                  style: context.typo.subHeader15.bold.copyWith(color: colors.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              14.sizedHeight,
              AppButton(
                title: strings.terminalOpenNew,
                prefix: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.add, color: colors.onPrimary),
                ),
                onTap: () => Navigator.pop(context, const OpenNewSession()),
              ),
            ],
          ),
        ),
      );
    },
  );
}
