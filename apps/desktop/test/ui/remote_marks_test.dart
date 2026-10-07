import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/remote_marks.dart';
import 'package:xterm/xterm.dart';

final devbox = SshTarget.parse('devbox')!;

PaneSession pane({
  SessionRemote? remote,
  int? exitCode,
  bool everConnected = true,
}) => PaneSession(
  id: 7,
  index: 1,
  shell: 'ssh',
  title: 'zsh',
  origin: SessionOrigin.desktop,
  phoneAttached: false,
  runningCommand: false,
  driver: DriverSide.desktop,
  terminal: DesktopTerminal(platform: TerminalTargetPlatform.macos),
  selection: TerminalController(),
  remote: remote,
  exitCode: exitCode,
  everConnected: everConnected,
);

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('SSH and tmux marks; nothing for a local pane (UI-A8 §2.1)', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(RemoteMark(pane(remote: SessionRemote(launch: SshLaunch(devbox))))),
    );
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    expect(find.byTooltip('SSH: devbox'), findsOneWidget);
    await tester.pumpWidget(
      app(
        RemoteMark(
          pane(
            remote: SessionRemote(launch: TmuxLaunch('main', host: devbox)),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.view_quilt_outlined), findsOneWidget);
    expect(find.byTooltip('tmux: main · devbox'), findsOneWidget);
    await tester.pumpWidget(
      app(
        RemoteMark(
          pane(remote: const SessionRemote(launch: TmuxLaunch('main'))),
        ),
      ),
    );
    expect(find.byTooltip('tmux: main'), findsOneWidget);
    await tester.pumpWidget(app(RemoteMark(pane())));
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('control characters in server-supplied names are stripped', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        RemoteMark(
          pane(
            remote: const SessionRemote(launch: TmuxLaunch('ma\u001b[31min')),
          ),
        ),
      ),
    );
    expect(find.byTooltip('tmux: ma[31min'), findsOneWidget);
  });

  testWidgets('the connecting dot is a 4 px dot in the 8 px box', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ConnectingDot()));
    expect(
      tester.getSize(find.byKey(const Key('dot.connecting'))),
      const Size(8, 8),
    );
  });

  test('semantics suffix and announcements (UI-A8 §8)', () {
    final connecting = pane(
      remote: SessionRemote(launch: SshLaunch(devbox)),
      everConnected: false,
    );
    final connected = pane(
      remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
    );
    final lost = pane(
      remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
      exitCode: 255,
    );
    expect(
      remoteSemantics(en, connecting),
      ', on devbox, Connecting to devbox',
    );
    expect(remoteSemantics(en, connected), ', on devbox');
    expect(remoteSemantics(en, lost), ', on devbox, Lost connection to devbox');
    expect(remoteSemantics(en, pane()), '');
    expect(
      remoteAnnouncement(en, connecting, connected),
      'Connected to devbox',
    );
    expect(
      remoteAnnouncement(en, connected, lost),
      'Lost connection to devbox',
    );
    expect(remoteAnnouncement(en, lost, connected), 'Reconnected to devbox');
    expect(remoteAnnouncement(en, connected, connected), isNull);
    expect(remoteAnnouncement(en, null, connected), isNull);
  });
}
