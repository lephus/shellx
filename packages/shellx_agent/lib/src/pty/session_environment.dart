/// Environment for a new terminal session (spec §7): the agent's own
/// environment plus `TERM=xterm-256color`, `COLORTERM=truecolor`,
/// `LANG=en_US.UTF-8` when LANG is unset or empty, `SHELLX=1`, and (A7 D29)
/// `SHELLX_PANE_ID` / `SHELLX_TAB_ID` so programs in the pane can target it.
Map<String, String> buildSessionEnvironment(
  Map<String, String> base, {
  int? paneId,
  int? tabId,
}) {
  final environment = Map<String, String>.of(base);
  environment['TERM'] = 'xterm-256color';
  environment['COLORTERM'] = 'truecolor';
  if ((environment['LANG'] ?? '').isEmpty) {
    environment['LANG'] = 'en_US.UTF-8';
  }
  environment['SHELLX'] = '1';
  if (paneId != null) environment['SHELLX_PANE_ID'] = '$paneId';
  if (tabId != null) environment['SHELLX_TAB_ID'] = '$tabId';
  return environment;
}
