import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../window_router.dart';
import 'terminal_intents.dart';
import 'terminal_workspace_config.dart' show WindowAction;

/// A8 D41: the actions of "Connect over SSH…" (⌘⇧K) and "Attach tmux
/// session…". Kept apart from the page. A dialog or confirm already open
/// keeps the keyboard: the key is consumed and nothing changes (a login or
/// onboarding route is not replaced by a question it did not ask).
Map<Type, Action<Intent>> sshWindowActions(
  WidgetRef ref, {
  required void Function() closePanel,
}) {
  void open(SshDialogTab tab) {
    final router = ref.read(windowRouterProvider.notifier);
    if (ref.read(windowRouterProvider).dialogOpen) return;
    closePanel();
    router.open(SshConnectRoute(tab));
  }

  return <Type, Action<Intent>>{
    OpenSshConnectIntent: WindowAction<OpenSshConnectIntent>(
      (_) => open(SshDialogTab.ssh),
      null,
    ),
    OpenTmuxAttachIntent: WindowAction<OpenTmuxAttachIntent>(
      (_) => open(SshDialogTab.tmux),
      null,
    ),
  };
}
