import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:xterm/xterm.dart';

import 'sidebar_test_harness.dart';

void main() {
  setUpSidebar();

  for (final split in [false, true]) {
    testSidebar(
      'a reconnect keeps the TerminalView mounted: state, scroll controller '
      'and focus unchanged (A8 D22, split: $split)',
      (t) async {
        final devbox = SshTarget.parse('devbox')!;
        local.add(
          local.summary(
            1,
            origin: SessionOrigin.desktop,
            remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
          ),
        );
        await pumpSidebar(t);
        if (split) {
          await container
              .read(terminalTabsProvider.notifier)
              .split(SplitAxis.row, local: true);
          container.read(terminalTabsProvider.notifier).focusPane(1);
          await t.pump();
          await t.pump();
        }
        final terminal = tabs().tabs.first.panes[1]!.terminal;
        Finder view() => find.byWidgetPredicate(
          (w) => w is TerminalView && identical(w.terminal, terminal),
        );
        final before = t.state(view());
        final scroll = t.widget<TerminalView>(view()).scrollController;
        final focus = t.widget<TerminalView>(view()).focusNode;
        final hadFocus = focus?.hasFocus;
        local.summaries.removeWhere((s) => s.id == 1);
        local.views[1]!.end(255);
        await t.pump();
        await t.pump();
        final tabsNotifier = container.read(terminalTabsProvider.notifier);
        final fresh = await t.runAsync(() => tabsNotifier.reconnect(1));
        await t.pump();
        await t.pump();
        expect(fresh, isNotNull);
        expect(identical(t.state(view()), before), isTrue);
        expect(t.widget<TerminalView>(view()).scrollController, scroll);
        expect(t.widget<TerminalView>(view()).focusNode, focus);
        expect(focus?.hasFocus, hadFocus);
      },
    );
  }
}
