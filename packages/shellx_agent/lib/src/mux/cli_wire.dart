import 'mux_messages.dart';

/// A7 D4: the CLI API version, separate from A5b's `protocol`. Bump only
/// for a breaking change; additions go in [kCliCaps].
const int kCliApi = 1;

abstract final class CliType {
  static const apiVersion = 'api.version';
  static const cliNotify = 'cli.notify';
  static const cliEventsSubscribe = 'cli.events.subscribe';
  static const event = 'event';
  static const uiLs = 'ui.ls';
  static const uiTabNew = 'ui.tab.new';
  static const uiTabRename = 'ui.tab.rename';

  /// A12 D18: a tab's description and status.
  static const uiTabMeta = 'ui.tab.meta';
  static const uiPaneSplit = 'ui.pane.split';
  static const uiFocus = 'ui.focus';
  static const uiClose = 'ui.close';
  static const uiPaneSend = 'ui.pane.send';
  static const uiPaneRead = 'ui.pane.read';
  static const uiPaneWait = 'ui.pane.wait';
  static const uiWorkspaceNew = 'ui.workspace.new';
  static const uiWorkspaceRename = 'ui.workspace.rename';
  static const uiWorkspaceMove = 'ui.workspace.move';
  static const uiNotify = 'ui.notify';
  static const uiEventsSubscribe = 'ui.events.subscribe';

  /// A9 D39.
  static const uiConfigCheck = 'ui.config.check';
  static const uiConfigReload = 'ui.config.reload';
  static const uiConfigShow = 'ui.config.show';
  static const uiBrowserPrefix = 'ui.browser.';

  /// A8 D22, D33.
  static const uiSshOpen = 'ui.ssh.open';
  static const uiTmuxList = 'ui.tmux.list';
  static const uiTmuxAttach = 'ui.tmux.attach';

  /// A12 D4: a coding agent's hook event, normalised by `shellx agent-event`.
  static const uiAgentEvent = 'ui.agent.event';

  /// D3: what a `cli` client may send. Everything else is `forbidden`.
  static bool allowedForCli(String t) =>
      t.startsWith('api.') ||
      t.startsWith('cli.') ||
      t.startsWith('ui.') ||
      t == MuxType.daemonStatus;
}

abstract final class CliError {
  static const forbidden = 'forbidden';
  static const cliDisabled = 'cli_disabled';
  static const noUi = 'no_ui';
  static const timeout = 'timeout';
  static const exited = 'exited';
  static const runningCommand = 'running_command';
  static const noRoom = 'no_room';
  static const ambiguous = 'ambiguous';

  /// A8 D3, D25: no ssh binary here / no tmux there / the listing failed.
  static const sshUnavailable = 'ssh_unavailable';
  static const tmuxUnavailable = 'tmux_unavailable';
  static const tmuxFailed = 'tmux_failed';

  /// The asking client went away (a `wait`, an open waiting its turn):
  /// nobody reads this answer.
  static const cancelled = 'cancelled';
}

/// D4: what this host serves (the CLI checks before sending). No
/// `ui.browser` until A6 adds browser panes (the CLI then exits 7).
const List<String> kCliCaps = [
  CliType.cliNotify,
  CliType.cliEventsSubscribe,
  CliType.uiLs,
  CliType.uiTabNew,
  CliType.uiTabRename,
  CliType.uiTabMeta,
  CliType.uiPaneSplit,
  CliType.uiFocus,
  CliType.uiClose,
  CliType.uiPaneSend,
  CliType.uiPaneRead,
  CliType.uiPaneWait,
  CliType.uiWorkspaceNew,
  CliType.uiWorkspaceRename,
  CliType.uiWorkspaceMove,
  'ui.config',
  'ui.ssh',
  'ui.tmux',
  'ui.agent',
];

MuxMessage cliResult(int? q, [Map<String, Object?> fields = const {}]) =>
    MuxMessage(MuxType.result, q: q, fields: fields);

MuxMessage cliErrorMessage(int? q, String code, [String? message]) =>
    MuxMessage(
      MuxType.error,
      q: q,
      fields: {'code': code, 'message': ?message},
    );
