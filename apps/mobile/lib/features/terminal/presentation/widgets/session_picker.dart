import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
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

/// Terminal sharing §9.1: the main line of a desktop terminal, "app — title"; a missing part
/// leaves the other, and with neither the shell's name.
String desktopSessionLabel(SessionInfo session) {
  final parts = [session.app, session.title].where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? session.shell : parts.join(' — ');
}

/// Spec §9.2 #4 and terminal sharing §9.1 / design "Terminal trên máy tính": the bottom sheet
/// offering the sessions not open as tabs, in two groups — "Terminal trên máy tính" (or, without any,
/// a hint picked by `desktop_sharing`) and "Phiên ShellX" — then "Phiên mới". Returns null when
/// dismissed.
Future<SessionChoice?> showSessionPicker(BuildContext context, SessionListing listing, {DateTime? now}) {
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
      final desktop = listing.desktop;
      final shellx = listing.shellx;
      final hint = switch (listing.desktopSharing) {
        null => strings.pickerHintUpdateDesktop,
        false => strings.pickerHintSharingOff,
        true => strings.pickerHintOpenNewWindow,
      };
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.pickerTitle(listing.sessions.length), style: context.typo.heading20.heavy),
              6.sizedHeight,
              Text(strings.pickerSubtitle, style: context.typo.subHeader15.copyWith(color: colors.secondaryText)),
              14.sizedHeight,
              _GroupHeader(strings.pickerDesktopGroup),
              8.sizedHeight,
              _Group(
                children: desktop.isEmpty
                    ? [_Hint(key: const ValueKey('picker-desktop-hint'), text: hint)]
                    : [
                        for (final session in desktop)
                          _SessionRow(
                            session: session,
                            label: desktopSessionLabel(session),
                            desktop: true,
                            now: at,
                          ),
                      ],
              ),
              if (shellx.isNotEmpty) ...[
                14.sizedHeight,
                _GroupHeader(strings.pickerShellxGroup),
                8.sizedHeight,
                _Group(
                  children: [
                    for (final session in shellx)
                      _SessionRow(
                        session: session,
                        label: '${session.shell} ${session.index}',
                        desktop: false,
                        now: at,
                      ),
                  ],
                ),
              ],
              14.sizedHeight,
              AppButton(
                title: strings.pickerNewSession,
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

/// Design `.list-h`.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText, letterSpacing: 0.8),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: colors.divider),
            child,
          ],
        ],
      ),
    );
  }
}

/// No desktop terminal to offer: why, and what to do about it.
class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(Icons.desktop_windows_outlined, size: 20, color: colors.secondaryText)),
          10.sizedWidth,
          Expanded(
            child: Text(text, style: context.typo.paragraph13.copyWith(color: colors.secondaryText)),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.label, required this.desktop, required this.now});

  final SessionInfo session;
  final String label;
  final bool desktop;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return InkWell(
      key: ValueKey('picker-session-${session.id}'),
      onTap: () => Navigator.pop(context, AttachSession(session)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(
            children: [
              if (desktop) ...[
                Icon(
                  Icons.desktop_windows_outlined,
                  size: 20,
                  color: colors.secondaryText,
                  semanticLabel: strings.desktopTerminalLabel,
                ),
                10.sizedWidth,
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                          formatLastSeen(strings, DateTime.fromMillisecondsSinceEpoch(session.createdAt), now),
                        ),
                        if (session.attached) strings.pickerAttachedElsewhere,
                      ].join(' · '),
                      style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
              10.sizedWidth,
              Text(strings.pickerOpen, style: context.typo.subHeader15.bold.copyWith(color: colors.link)),
            ],
          ),
        ),
      ),
    );
  }
}
