import 'package:shellx_agent/shellx_agent.dart';

import 'session_core.dart';

/// V2-2 D1, background service: phones' AI messages go to the attached
/// window that serves AI, and what it answers comes back. One forwarder is
/// both [server]'s (the window's `ai.serve`, `ai.out` and `ai.push`) and the
/// target of [core]'s slot (what every runtime's router sends), so the
/// window's answers reach the phones that asked. Its pushes go out with this
/// service's own notifications, under their limit.
///
/// Called once, before the server listens and the agent starts, so no window
/// or phone reaches the service before the slot has its target.
MuxAiForwarder installDaemonAi(MuxServer server, SessionCore core) {
  final forwarder = MuxAiForwarder(
    onPush: (push) => core.notifications?.aiNotice(push),
  );
  server.ai = forwarder;
  core.ai.target = forwarder;
  return forwarder;
}
