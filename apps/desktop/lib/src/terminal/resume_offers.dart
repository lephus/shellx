import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cli/ui_command_handler.dart' show uiCommandHandlerProvider;
import '../config/config_controller.dart' show shellxConfigProvider;
import '../config/shellx_config.dart' show AgentResume;
import '../restore/restore_snapshot.dart'
    show SavedAgent, SavedPane, isRestorableCwd;
import 'agent_status.dart';
import 'agent_status_notifier.dart';
import 'terminal_tabs.dart';

// A12 D13–D14: after a restart, an agent that was running in a pane gets a
// banner with one button. Nothing runs by itself: the command is typed and
// run only when the user presses it.

/// The command that resumes [session] of [k], built from fixed words and
/// the id. The id comes from a process the user does not control, so it
/// enters a command only after the strict pattern (`kSessionId`: letters,
/// digits and `._:-`, never a leading `-`): no shell metacharacter can be in
/// it, so no quoting is needed and the line reads the same in zsh, bash,
/// fish, PowerShell and cmd. Null for any other id.
///
/// Gemini CLI: its hooks may not hand over a session id ShellX can use; then
/// no offer is made at all (an id is only ever saved from a valid hook
/// event), and `gemini --resume` itself is unverified (spec D6).
///
/// The words are those of spec D6. ⚠ Manual: confirm each against the real
/// agent (Claude Code `--resume`, Codex `resume`, Gemini CLI `--resume`,
/// OpenCode `--session`); a wrong word only makes the agent print an error.
String? resumeCommand(AgentKind k, String session) {
  if (!isValidSessionId(session)) return null;
  return switch (k) {
    AgentKind.claude => 'claude --resume $session',
    AgentKind.codex => 'codex resume $session',
    AgentKind.gemini => 'gemini --resume $session',
    AgentKind.opencode => 'opencode --session $session',
  };
}

/// What a pane offers to resume. [session] came from an agent's hook:
/// [toString] shows nothing.
@immutable
final class ResumeOffer {
  const ResumeOffer(this.kind, this.session);
  final AgentKind kind;
  final String session;

  @override
  String toString() => '…';
}

/// Whether pane [pane] is at an idle prompt: its shell reported itself (a
/// folder is known) and no command runs. Resume types only then; there is no
/// quiet-window fallback, because a line typed into a running program would
/// go to that program.
final resumeReadyProvider = Provider.family<bool, int>((ref, pane) {
  final p = ref.watch(
    terminalTabsProvider.select((s) => s.tabOfSession(pane)?.panes[pane]),
  );
  return p != null && !p.exited && p.cwd != null && !p.runningCommand;
});

/// The offers on screen, by pane (session) id.
final resumeOffersProvider =
    NotifierProvider<ResumeOffers, Map<int, ResumeOffer>>(ResumeOffers.new);

class ResumeOffers extends Notifier<Map<int, ResumeOffer>> {
  @override
  Map<int, ResumeOffer> build() {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final subs = [
      // The first real key typed into the pane answers "no".
      tabs.userInputs.listen(dismiss),
      // A8 D22: a reconnected pane is the same pane.
      tabs.paneReplacements.listen((r) {
        final offer = state[r.from];
        if (offer == null) return;
        state = {
          for (final e in state.entries)
            if (e.key != r.from) e.key: e.value,
          r.to: offer,
        };
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    });
    // A pane that closed takes its offer with it.
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, tabs) {
      final gone = state.keys.where((p) => tabs.tabOfSession(p) == null);
      if (gone.isNotEmpty) _drop(gone.toList());
    });
    // An agent that reports from the pane has started: nothing to offer.
    ref.listen<Map<int, AgentPane>>(agentStatusProvider, (_, records) {
      final started = state.keys.where((p) {
        final r = records[p];
        return r != null && r.state != AgentState.unknown;
      });
      if (started.isNotEmpty) _drop(started.toList());
    });
    return const {};
  }

  void add(int pane, ResumeOffer offer) {
    if (!ref.mounted) return;
    state = {...state, pane: offer};
  }

  void _drop(List<int> panes) {
    state = {
      for (final e in state.entries)
        if (!panes.contains(e.key)) e.key: e.value,
    };
  }

  /// The offer goes; the record of the unseen session stays (the next
  /// start event replaces it).
  void remove(int pane) {
    if (state.containsKey(pane)) _drop([pane]);
  }

  /// "Dismiss", Esc, a key typed into the pane: the offer and the record
  /// of the session it came from go (D13).
  void dismiss(int pane) {
    if (!state.containsKey(pane)) return;
    _drop([pane]);
    ref.read(agentStatusProvider.notifier).dropRestored(pane);
  }

  /// The button: types the command and presses Enter, once. The offer goes
  /// first, so a second press cannot type it again.
  void resume(int pane) {
    final offer = state[pane];
    if (offer == null || !ref.read(resumeReadyProvider(pane))) return;
    remove(pane);
    final command = resumeCommand(offer.kind, offer.session);
    if (command == null) return;
    // The same path as `--cmd` of a new tab: waits for a shell that is
    // ready, sends the text through the paste sender, then Enter.
    ref.read(uiCommandHandlerProvider).onCommand?.call(pane, command);
  }
}

/// The agent each local pane ran, as the layout saves it: records with a
/// valid session id.
Map<int, SavedAgent> savedAgents(Map<int, AgentPane> records) => {
  for (final MapEntry(key: pane, value: r) in records.entries)
    if (r.session != null && isValidSessionId(r.session!))
      pane: (kind: r.agent, session: r.session!),
};

/// After the tabs of a snapshot are back (A12 D13, D14): for each reopened
/// pane that had an agent, a record of its session (state unknown, never
/// shown) and, unless the shells survived ([reattach]) or the pane is not
/// where it was, an offer. [keyBySession] maps the new sessions to the saved
/// pane keys of [panes].
///
/// No offer for: `agent-resume = off`, an SSH or tmux pane (the command
/// would run on this machine, the wrong place), a pane whose folder was not
/// restored (the session is tied to its folder), or a reattach (the agent
/// is still running there).
void restoreAgentSessions(
  Ref ref, {
  required Iterable<SavedPane> panes,
  required Map<int, String> keyBySession,
  required bool reattach,
}) {
  if (!ref.mounted) return;
  if (ref.read(shellxConfigProvider).config.agentResume == AgentResume.off) {
    return;
  }
  final byKey = {for (final p in panes) p.key: p};
  final tabs = ref.read(terminalTabsProvider);
  final status = ref.read(agentStatusProvider.notifier);
  final offers = ref.read(resumeOffersProvider.notifier);
  for (final MapEntry(key: id, value: key) in keyBySession.entries) {
    final saved = byKey[key];
    final agent = saved?.agent;
    if (saved == null || agent == null || saved.launch != null) continue;
    final pane = tabs.tabOfSession(id)?.panes[id];
    if (pane == null || pane.exited || pane.remote != null) continue;
    final cwd = saved.cwd;
    final here = cwd != null && isRestorableCwd(cwd);
    if (!reattach && !here) continue;
    status.seedRestored(id, agent.kind, agent.session);
    if (!reattach) offers.add(id, ResumeOffer(agent.kind, agent.session));
  }
}
