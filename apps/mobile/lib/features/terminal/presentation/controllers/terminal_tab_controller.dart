import 'dart:async';
import 'dart:convert';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_output_feed.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/xterm.dart';

enum TabNotice {
  exited,
  sessionEnded,
  takenOver,

  /// The computer closed the session (ShellX tab) or disconnected this phone from it (desktop tab:
  /// the terminal keeps running, so it can be reattached).
  closedByHost,
  failed,

  /// Desktop tab: the terminal window was closed on the computer (`session.exited`).
  desktopClosed,

  /// Desktop tab: the agent lost the terminal (`terminal_gone`) or no longer knows it.
  terminalGone,
}

/// Why a tab stopped being live; rendered over the terminal by the UI.
final class TabBanner {
  const TabBanner(this.notice, {this.exitCode, this.errorCode, this.detail});

  final TabNotice notice;
  final int? exitCode;
  final AppErrorCode? errorCode;
  final String? detail;
}

/// The text typed in the voice composer for one terminal (A11 D29). In memory only, never written to disk
/// or logged: it may hold a password.
final class DraftHolder {
  String value = '';

  @override
  String toString() => '…';
}

/// Binds one [TabHandle] to an xterm terminal: output → screen, keys → input,
/// size → resize, lifecycle events → [banner].
class TerminalTabController extends Controller {
  TerminalTabController({
    required MachineSession machine,
    required TabHandle handle,
    required ModifierSource modifiers,
    required int cols,
    required int rows,
    this.resizeDebounce = const Duration(milliseconds: 150),
  }) : _machine = machine,
       _modifiers = modifiers,
       id = handle.id,
       hasSession = true,
       isDesktop = handle.kind == SessionKind.desktop,
       _shell = handle.shell,
       _index = handle.index,
       _app = handle.app,
       _windowTitle = handle.title {
    _terminal = signal(_createTerminal(cols, rows));
    _lastSent = (cols: cols, rows: rows);
    _bind(handle);
  }

  /// Attaching failed with `session_not_found` (the agent
  /// restarted). Shows "Phiên đã kết thúc" and can only be closed.
  TerminalTabController.ended({
    required MachineSession machine,
    required SessionInfo session,
    required ModifierSource modifiers,
    this.resizeDebounce = const Duration(milliseconds: 150),
  }) : _machine = machine,
       _modifiers = modifiers,
       id = session.id,
       hasSession = true,
       isDesktop = session.kind == SessionKind.desktop,
       _shell = session.shell,
       _index = session.index,
       _app = session.app,
       _windowTitle = session.title {
    _terminal = signal(_createTerminal(80, 24));
    _banner.value = TabBanner(isDesktop ? TabNotice.terminalGone : TabNotice.sessionEnded);
  }

  /// Opening a new session failed on the computer (spec §12 `spawn_failed`: the agent answers
  /// the open with an error that carries no session id). No session exists: the tab shows the
  /// reason with "Đóng tab" / "Mở phiên mới" and never sends anything. [id] is a local id the
  /// workspace hands out (negative, so it never matches a session of the machine).
  TerminalTabController.failed({
    required MachineSession machine,
    required this.id,
    required AppErrorException error,
    required ModifierSource modifiers,
    this.resizeDebounce = const Duration(milliseconds: 150),
  }) : _machine = machine,
       _modifiers = modifiers,
       hasSession = false,
       isDesktop = false,
       _shell = '',
       _index = 0,
       _app = '',
       _windowTitle = '' {
    _terminal = signal(_createTerminal(80, 24));
    _banner.value = TabBanner(TabNotice.failed, errorCode: error.code, detail: error.message);
  }

  final int id;

  /// What the composer holds for this terminal; dropped with the tab.
  final DraftHolder draft = DraftHolder();

  /// False for a [TerminalTabController.failed] tab: there is no session on the machine to close,
  /// and its title is left to the UI (empty [title]).
  final bool hasSession;

  /// A terminal window open on the computer (terminal sharing §9.2): `×` only detaches from it,
  /// and the computer may take the size back ([driver]).
  final bool isDesktop;
  final Duration resizeDebounce;
  final MachineSession _machine;
  final ModifierSource _modifiers;
  final String _shell;
  final int _index;
  final String _app;
  final String _windowTitle;

  /// Selection state for long-press copy (spec §9.4).
  final TerminalController selection = TerminalController();

  /// The terminal view's scroll position, so the keyboard cover knows when the view is scrolled up (A11 D31).
  final ScrollController scroll = ScrollController();
  late final Signal<ShellxTerminal> _terminal;
  final Signal<TabBanner?> _banner = signal(null);
  final Signal<bool> _bound = signal(false);
  final Signal<String?> _oscTitle = signal(null);

  /// A11 D28: output arrived since this tab was last looked at (computed on the phone, never sent anywhere).
  final Signal<bool> _unseen = signal(false);
  bool _viewed = true;

  /// The phone drives right after any attach: taking over at an unchanged size brings no
  /// `session.driver` (ledger "Ghi cho P5").
  final Signal<DriverSide> _driver = signal(DriverSide.phone);
  late final Computed<bool> _isLive = computed(() => _bound.value && _banner.value == null);
  late final Computed<bool> _showDriverBanner = computed(
    () => isDesktop && _isLive.value && _driver.value == DriverSide.desktop,
  );
  late final Computed<String> _title = computed(() => _oscTitle.value ?? _fallbackTitle);

  /// Agent quick reply §3: the coding agent's state in this session, as the desktop tells it (`agent.state`,
  /// `session.attached`); null when none shows or the desktop is older. Never the agent's words.
  final Signal<AgentWireState?> _agentState = signal(null);

  /// Agent quick reply D2: "⌨" put the extra keys back for the current question.
  final Signal<bool> _replyDismissed = signal(false);
  late final Computed<bool> _showReplyBar = computed(
    () => _isLive.value && _agentState.value == AgentWireState.needsInput && !_replyDismissed.value,
  );

  /// Sent a size since the computer last took it back: typing claims only once.
  bool _claimed = false;

  /// A10 D29: output reaches xterm in budgeted pieces, the foreground tab first. Writes to whichever
  /// terminal is current (a `session.reset` swaps it).
  late final TerminalOutputFeed _feed = TerminalOutputFeed((text) {
    if (!_disposed) _terminal.peek().write(text);
  });
  TabHandle? _handle;
  StreamSubscription<TabEvent>? _events;
  Timer? _resizeTimer;

  /// The user changed the phone's size since the last send ([noteSizeIntent]): while the computer
  /// drives, only such a grid change is sent.
  bool _sizeIntent = false;
  ({int cols, int rows})? _lastSent;
  bool _disposed = false;

  /// Replaced by a fresh instance on `session.reset`.
  ReadonlySignal<ShellxTerminal> get terminal => _terminal;
  ReadonlySignal<TabBanner?> get banner => _banner;
  ReadonlySignal<bool> get isLive => _isLive;

  /// "New output": text came while the tab was not in front of the user ([setViewed]); cleared when it is.
  ReadonlySignal<bool> get unseen => _unseen;

  /// Spec §7: the terminal title (OSC 0/2) if the shell set one, else "`<shell> <index>`"; empty
  /// for a tab without a session ([hasSession]), which has neither.
  ReadonlySignal<String> get title => _title;

  /// Who sets the desktop terminal's size now.
  ReadonlySignal<DriverSide> get driver => _driver;

  /// Agent quick reply §3: the agent's live state (the dots of the tab strip and the machine list).
  ReadonlySignal<AgentWireState?> get agentState => _agentState;

  /// Agent quick reply D2: the reply bar takes the extra keys' place: the tab is live, its agent waits for
  /// the user and "⌨" was not tapped for this question.
  ReadonlySignal<bool> get showReplyBar => _showReplyBar;

  /// "⌨": the extra keys again, until the agent asks the next time (leaves `needs_input` and comes back).
  void dismissReplyBar() {
    if (!_disposed) _replyDismissed.value = true;
  }

  /// "Máy tính đang dùng terminal này": a live desktop tab whose size the computer has taken.
  ReadonlySignal<bool> get showDriverBanner => _showDriverBanner;

  /// "Gắn lại" is offered: another device took the session, or the computer disconnected this phone
  /// from a desktop terminal that keeps running.
  bool get canReattach => switch (_banner.peek()?.notice) {
    TabNotice.takenOver => true,
    TabNotice.closedByHost => isDesktop,
    _ => false,
  };

  /// Closing this tab leaves a terminal running on the computer ("Terminal vẫn chạy trên máy tính."):
  /// a desktop tab whose terminal was not closed or lost.
  bool get leavesTerminalRunning =>
      isDesktop && !const {TabNotice.desktopClosed, TabNotice.terminalGone}.contains(_banner.peek()?.notice);

  /// Desktop: the window title, else the app, else "`<shell> <index>`".
  String get _fallbackTitle {
    if (!hasSession) return '';
    if (isDesktop && _windowTitle.isNotEmpty) return _windowTitle;
    if (isDesktop && _app.isNotEmpty) return _app;
    return '$_shell $_index';
  }

  ShellxTerminal _createTerminal(int cols, int rows) {
    final terminal = ShellxTerminal(modifiers: _modifiers)..resize(cols, rows);
    return terminal
      ..onOutput = _onUserInput
      ..onResize = _onResize
      ..onTitleChange = _onTitle;
  }

  void _bind(TabHandle handle) {
    _handle = handle;
    _events = handle.events.listen(_onEvent);
    _bound.value = true;
  }

  void _onEvent(TabEvent event) {
    switch (event) {
      case TabOutput(:final text, :final replay):
        _feed.add(text);
        // The catch-up a re-attach replays (spec §6.4: up to the head `session.attached` carries) is
        // output the tab already had, not new output: it does not mark the tab.
        if (!_viewed && !replay && text.isNotEmpty && !_unseen.peek()) _unseen.value = true;
      case TabReset():
        _feed.clear();
        final current = _terminal.peek();
        _terminal.value = _createTerminal(current.viewWidth, current.viewHeight);
        selection.clearSelection();
      case TabExited(:final exitCode):
        _agentState.value = null;
        _feed.drain(); // the banner never comes before the last output
        // "Closed on the computer" says more than the exit code that follows it.
        if (_banner.peek()?.notice != TabNotice.closedByHost) {
          _banner.value = isDesktop
              ? const TabBanner(TabNotice.desktopClosed)
              : TabBanner(TabNotice.exited, exitCode: exitCode);
        }
      case TabDriver(:final by):
        _claimed = false;
        _driver.value = by;
        if (by == DriverSide.phone) _sendViewSizeIfChanged();
      case TabAgent(:final state):
        // A new question (not the same one told again, as a re-attach does) brings the bar back.
        if (state != AgentWireState.needsInput) _replyDismissed.value = false;
        _agentState.value = state;
      case TabDetached(:final reason):
        _agentState.value = null; // another device or the computer has it now; the attach tells again
        _banner.value = TabBanner(switch (reason) {
          DetachReason.takenOver => TabNotice.takenOver,
          DetachReason.closedByHost => TabNotice.closedByHost,
          DetachReason.terminalGone => TabNotice.terminalGone,
        });
      case TabError(:final code, :final message):
        _agentState.value = null;
        _banner.value = code == AppErrorCode.sessionNotFound
            ? TabBanner(isDesktop ? TabNotice.terminalGone : TabNotice.sessionEnded)
            : TabBanner(TabNotice.failed, errorCode: code, detail: message);
    }
  }

  void _onUserInput(String data) {
    if (!_isLive.peek()) return;
    _feed.noteInput();
    if (!_claimed) claimSize();
    _machine.input(id, utf8.encode(data));
  }

  /// Terminal sharing §9.2: a tap on the terminal or a keystroke while the computer drives sends
  /// the phone's size, even when it did not change, so the agent hands the size back to the phone.
  /// The banner stays until `session.driver {by: phone}` arrives. Nothing while the phone drives.
  void claimSize() {
    if (_disposed || !_showDriverBanner.peek()) return;
    final current = _terminal.peek();
    final cols = current.viewWidth;
    final rows = current.viewHeight;
    if (cols < 1 || rows < 1) return;
    _claimed = true;
    _sizeIntent = false;
    _lastSent = (cols: cols, rows: rows);
    _machine.resize(id, cols, rows);
  }

  /// The page saw the user change the phone's size: the orientation, the keyboard (bottom inset)
  /// or the font size (pinch, "Aa"). The next grid change is then sent even while the computer
  /// drives, which takes the size back (terminal sharing §5.5). The banner showing or hiding, a
  /// view mounted again (switching tabs, `session.reset`) carry no intent.
  void noteSizeIntent() {
    if (_disposed) return;
    _sizeIntent = true;
  }

  /// The phone has the size again: a size the view took meanwhile (laid out after the claim, its
  /// debounced resize not sent yet) goes out now, so the PTY matches what the phone shows.
  void _sendViewSizeIfChanged() {
    final current = _terminal.peek();
    _sendResize(current.viewWidth, current.viewHeight);
  }

  void _onResize(int cols, int rows, int pixelWidth, int pixelHeight) {
    // Coalesce the burst of sizes produced while the keyboard slides or the
    // phone rotates; only the final size is sent.
    _resizeTimer?.cancel();
    _resizeTimer = Timer(resizeDebounce, () => _sendResize(cols, rows));
  }

  /// Never sends a size below 1×1 (a zero-sized viewport while the keyboard slides or the phone
  /// rotates), never repeats the last size.
  ///
  /// While the phone drives every grid change is sent. While the computer drives (terminal sharing
  /// §5.5: the phone takes the size when it attaches, types or changes size; §9.2: a tap or a
  /// keystroke, [claimSize]) a grid change is sent, and so claims the size, only after a user size
  /// intent ([noteSizeIntent]) since the last send: the banner's own row, a tab switched to or a
  /// view rebuilt by `session.reset` are not the phone changing size.
  void _sendResize(int cols, int rows) {
    if (_disposed || !_isLive.peek() || cols < 1 || rows < 1) return;
    if (_showDriverBanner.peek() && !_sizeIntent) return;
    final size = (cols: cols, rows: rows);
    if (size == _lastSent) return;
    _sizeIntent = false;
    _lastSent = size;
    _machine.resize(id, cols, rows);
  }

  void _onTitle(String title) {
    if (_disposed) return;
    _oscTitle.value = title.isEmpty ? null : title;
  }

  /// After `taken_over`, or `closed_by_host` on a desktop tab ([canReattach]): attach this phone
  /// again (another device gets `taken_over`). `shellx_client` re-attaches the same tab with
  /// `last_seq = received`, so the catch-up output arrives on the events we
  /// are still listening to and the current screen is kept; a `session.reset`
  /// replaces it as usual. Re-attaching returns the *same* `TabHandle`, so we
  /// only rebind the subscription when a different handle comes back —
  /// binding again on the same handle would deliver every later event twice.
  ///
  /// Only `AppErrorException(sessionNotFound)` (the session vanished) is
  /// handled here, ending the tab. Any other failure — in particular the
  /// `MachineConnectionException` `MachineClient.attach()` throws at once
  /// when there is no channel (`agentOffline`, `timeout`, …) — leaves the
  /// controller exactly as it was (same banner, still not live, subscription
  /// and screen unchanged, not disposed) and is rethrown, so the caller (the
  /// terminal page's "Gắn lại" button) can show it through the usual
  /// `ErrorText` mapping. A later `reattach()` call still works.
  Future<void> reattach() async {
    if (!canReattach) return;
    final current = _terminal.peek();
    final cols = current.viewWidth;
    final rows = current.viewHeight;
    try {
      final handle = await _machine.attach(id, cols: cols, rows: rows);
      if (_disposed) return;
      if (!identical(handle, _handle)) {
        unawaited(_events?.cancel());
        _bind(handle);
      }
      batch(() {
        _banner.value = null;
        _driver.value = DriverSide.phone;
      });
      _claimed = false;
      _lastSent = (cols: cols, rows: rows);
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.sessionNotFound) rethrow;
      if (!_disposed) _banner.value = TabBanner(isDesktop ? TabNotice.terminalGone : TabNotice.sessionEnded);
    }
  }

  /// The workspace tells which tab is in front (A10 D29).
  void setActive(bool active) => _feed.isActive = active;

  /// The workspace tells whether the user is looking at this tab: it is the active one and the page shows.
  void setViewed(bool viewed) {
    if (_disposed) return;
    _viewed = viewed;
    if (viewed && _unseen.peek()) _unseen.value = false;
  }

  void dispose() {
    _disposed = true;
    draft.value = ''; // a closed tab keeps nothing the composer may have held (a password)
    _feed.dispose();
    _resizeTimer?.cancel();
    unawaited(_events?.cancel());
    selection.dispose();
    scroll.dispose();
    _showDriverBanner.dispose();
    _showReplyBar.dispose();
    _agentState.dispose();
    _replyDismissed.dispose();
    _isLive.dispose();
    _title.dispose();
    _driver.dispose();
    _terminal.dispose();
    _banner.dispose();
    _bound.dispose();
    _oscTitle.dispose();
    _unseen.dispose();
  }
}
