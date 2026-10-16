import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

/// Opens an AI tab through the tab list (V2-1 D2, D3) and returns it.
TerminalTab openTestAiTab(
  ProviderContainer c, {
  String agentId = 'claude',
  String agentName = 'Claude',
  String title = 'New AI session',
  String? cwd = '/w/project',
  String? sessionId,
  String? workspace,
  bool select = true,
}) {
  final id = c
      .read(terminalTabsProvider.notifier)
      .openAiTab(
        agentId: agentId,
        agentName: agentName,
        title: title,
        cwd: cwd,
        sessionId: sessionId,
        workspace: workspace,
        select: select,
      );
  return c.read(terminalTabsProvider).tabs.firstWhere((t) => t.id == id);
}
