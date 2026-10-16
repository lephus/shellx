import 'package:shellx_agent/shellx_agent.dart';

import 'session_core.dart';

/// V2-4 E5, background service: the service holds the relay, so it hosts
/// the tool proxy. One proxy is the target of [core]'s slot (what every
/// runtime's router sends) and takes the window's lists (`tool.serve`); the
/// last list stays when the window quits, like the service's shells.
///
/// Called once, before the server listens and the agent starts.
ToolProxy installDaemonTools(MuxServer server, SessionCore core) {
  final proxy = ToolProxy();
  server.tools = proxy;
  core.tools.target = proxy;
  return proxy;
}
