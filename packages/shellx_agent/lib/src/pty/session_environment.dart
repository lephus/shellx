/// Environment for a new terminal session (spec §7): the agent's own
/// environment plus `TERM=xterm-256color`, `COLORTERM=truecolor`,
/// `LANG=en_US.UTF-8` when LANG is unset or empty, and `SHELLX=1`.
Map<String, String> buildSessionEnvironment(Map<String, String> base) {
  final environment = Map<String, String>.of(base);
  environment['TERM'] = 'xterm-256color';
  environment['COLORTERM'] = 'truecolor';
  if ((environment['LANG'] ?? '').isEmpty) {
    environment['LANG'] = 'en_US.UTF-8';
  }
  environment['SHELLX'] = '1';
  return environment;
}
