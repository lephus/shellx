/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pairing/pairing_code_manager.dart';
export 'src/pairing/pairing_id.dart';
export 'src/pty/process_pty.dart';
export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
export 'src/service/agent_events.dart';
export 'src/service/agent_service.dart';
export 'src/session/agent_sessions.dart';
export 'src/session/ring_buffer.dart';
export 'src/session/session_ids.dart';
export 'src/session/session_manager.dart';
export 'src/session/session_stream.dart';
export 'src/term/term_auth.dart';
export 'src/term/term_endpoint.dart';
export 'src/term/term_frames.dart';
export 'src/term/term_link.dart';
export 'src/term/term_messages.dart';
export 'src/term/desktop_session_manager.dart';
export 'src/term/osc_title.dart';
export 'src/term/term_server.dart';
export 'src/trust/trusted_store.dart';
