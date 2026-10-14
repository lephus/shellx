import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart' show Pty, ShellCommand;
import 'package:shellx_ai/host.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_folders.dart';
import '../../ai/ai_startup.dart';
import '../../terminal/desktop_terminal.dart';
import '../../terminal/terminal_appearance.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_style.dart';
import '../theme/shellx_desktop_theme.dart';

/// D8: the run sheet — a terminal of its own over the AI pane (a PTY and
/// xterm, as a terminal pane has; not in the pane tree, no background
/// session) that runs exactly [command]: an agent's terminal sign-in, or
/// its pinned install. Exit 0 calls [onDone]; another code keeps the sheet
/// with the code, "Try again" and "Close".
/// - ShellX never parses, logs or keeps what runs here (§5).
/// - The program gets a real terminal (`TERM=xterm-256color`,
///   `COLORTERM=truecolor`) on top of [command]'s environment; the agents
///   themselves keep the `TERM=dumb` of the login environment.
/// - The sheet asks for the keyboard once it is up (a button pressed from the
///   keyboard keeps it, and `autofocus` does nothing then).
class AiRunSheet extends ConsumerStatefulWidget {
  const AiRunSheet({
    super.key,
    required this.title,
    required this.command,
    required this.workingDirectory,
    this.makeFolder = false,
    this.failureNote,
    this.focusNode,
    required this.onDone,
    required this.onClose,
  });

  final String title;
  final AgentCommand command;
  final String workingDirectory;

  /// An install's folder (`<support>/ai/agents/<id>`) does not exist before
  /// the first install: it is made first.
  final bool makeFolder;

  /// Said before the exit code when the program fails ("Sign-in did not
  /// work.").
  final String? failureNote;

  /// The terminal's keyboard focus when its owner needs to reach it (the AI
  /// pane sends the window's focus requests here while the sheet is up);
  /// the sheet's own when null. Never disposed by the sheet.
  final FocusNode? focusNode;
  final VoidCallback onDone;
  final VoidCallback onClose;

  @override
  ConsumerState<AiRunSheet> createState() => _AiRunSheetState();
}

class _AiRunSheetState extends ConsumerState<AiRunSheet> {
  final _terminal = DesktopTerminal(maxLines: 2000);
  final _ownFocus = FocusNode(debugLabel: 'ai run sheet');
  Pty? _pty;
  StreamSubscription<String>? _output;

  /// The program runs (spawned, not exited).
  var _running = false;

  /// The exit code of a run that failed; null while it runs (or before).
  int? _failed;

  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void initState() {
    super.initState();
    _terminal
      ..onUserInput = _send
      ..onReply = _send
      ..onResize = (cols, rows, _, _) => _pty?.resize(cols, rows);
    // The program needs the keys. `autofocus` only applies while nothing
    // has the keyboard: a sign-in button activated from the keyboard keeps
    // it, and the next Enter would press the button again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    unawaited(_run());
  }

  @override
  void dispose() {
    unawaited(_output?.cancel());
    // Closed while it still runs: the program goes with the sheet.
    if (_running) _pty?.kill();
    _ownFocus.dispose();
    super.dispose();
  }

  void _send(String data) => _pty?.write(utf8.encode(data));

  Future<void> _run() async {
    final command = widget.command;
    try {
      if (widget.makeFolder) {
        await ref.read(aiMakeFolderProvider)(widget.workingDirectory);
      }
      if (!mounted) return;
      final pty = ref
          .read(aiPtyFactoryProvider)
          .spawn(
            ShellCommand(
              executable: command.executable,
              arguments: command.args,
              name: command.executable.split(RegExp(r'[/\\]')).last,
            ),
            workingDirectory: widget.workingDirectory,
            environment: {
              ...command.environment,
              'TERM': 'xterm-256color',
              'COLORTERM': 'truecolor',
            },
            cols: _terminal.viewWidth,
            rows: _terminal.viewHeight,
          );
      _pty = pty;
      _running = true;
      _output = const Utf8Decoder(
        allowMalformed: true,
      ).bind(pty.output).listen(_terminal.write);
      final code = await pty.exitCode;
      if (!identical(_pty, pty)) return;
      _running = false;
      if (!mounted) return;
      if (code == 0) {
        widget.onDone();
      } else {
        setState(() => _failed = code);
      }
    } on Object catch (error) {
      debugPrint('ShellX: run sheet did not start: ${error.runtimeType}');
      if (mounted) setState(() => _failed = -1);
    }
  }

  void _retry() {
    unawaited(_output?.cancel());
    _output = null;
    _pty = null;
    setState(() => _failed = null);
    _terminal.write('\r\n');
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(terminalAppearanceProvider);
    final style = desktopTerminalStyle(
      ref.watch(terminalFontSizeProvider),
      families: appearance.families,
      regular: appearance.regular,
      cellHeightPercent: appearance.cellHeightPercent,
    );
    final failed = _failed;
    return Container(
      key: const Key('ai.runSheet'),
      margin: const EdgeInsets.all(ShellxSpace.s16),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShellxSpace.s12,
              ShellxSpace.s8,
              ShellxSpace.s4,
              ShellxSpace.s4,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal,
                  size: 16,
                  color: ShellxDesktopColors.accent,
                ),
                const SizedBox(width: ShellxSpace.s6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: ShellxText.bodyStrong.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('ai.runSheet.close'),
                  tooltip: l10n.actionClose,
                  iconSize: 16,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s12),
            child: Text(
              l10n.aiRunSheetNote,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: ShellxSpace.s8),
          Expanded(
            child: ColoredBox(
              color: appearance.background,
              child: TerminalView(
                _terminal,
                focusNode: _focus,
                autofocus: true,
                theme: appearance.theme,
                textStyle: style,
                cursorType: appearance.cursor,
                padding: appearance.padding,
              ),
            ),
          ),
          if (failed != null)
            Padding(
              padding: const EdgeInsets.all(ShellxSpace.s8),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: ShellxDesktopColors.err,
                  ),
                  const SizedBox(width: ShellxSpace.s6),
                  Expanded(
                    child: Text(
                      [
                        ?widget.failureNote,
                        l10n.aiRunSheetFailed(failed),
                      ].join(' '),
                      key: const Key('ai.runSheet.failed'),
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.err,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('ai.runSheet.retry'),
                    onPressed: _retry,
                    child: Text(l10n.aiRetry),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
