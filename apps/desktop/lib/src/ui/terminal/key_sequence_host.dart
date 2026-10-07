import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/keybind_trigger.dart';
import '../../terminal/terminal_tabs.dart';
import '../../terminal/user_commands.dart';
import 'key_sequence.dart';
import 'shortcut_labels.dart';

/// The window's side of D28: feeds keys to [KeySequence] from the terminal
/// and from the rest of the window, announces a pending prefix, and ends the
/// wait on a focus change or a click. Kept apart from the page.
mixin WorkspaceSequences<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// Runs an intent through the window's actions (false: not applicable).
  bool invokeIntent(Intent intent);

  FocusNode? _lastFocus;

  void listenToSequences() {
    _lastFocus = FocusManager.instance.primaryFocus;
    FocusManager.instance.addListener(_cancelOnFocusChange);
    ref.listenManual(keySequenceProvider, (_, pending) {
      if (pending == null) return;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(
            context,
          ).sequencePendingAnnounce(chordLabel(pending, mac: isMacDesktop)),
          Directionality.of(context),
        ),
      );
    });
  }

  void disposeSequences() =>
      FocusManager.instance.removeListener(_cancelOnFocusChange);

  void _cancelOnFocusChange() {
    final now = FocusManager.instance.primaryFocus;
    if (identical(now, _lastFocus)) return;
    _lastFocus = now;
    if (!mounted) return;
    ref.read(keySequenceProvider.notifier).cancel();
  }

  /// The key hook for a terminal and for the rest of the window.
  KeyEventResult sequenceKey(KeyEvent event) {
    // D28: never inside a text field (inline rename, palette): Ctrl+A there
    // is the field's, and so is an input method's composition.
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    return ref
        .read(keySequenceProvider.notifier)
        .handle(
          event,
          invoke: invokeIntent,
          sendPrefix: (prefix) {
            final text = prefixText(prefix);
            if (text != null) {
              sendTextToFocused(ref.read(terminalTabsProvider), text);
            }
          },
        );
  }

  /// Wraps the window body: the sidebar's keys reach [sequenceKey] too, and
  /// a click ends a pending prefix.
  Widget sequenceScope(Widget child) => Listener(
    onPointerDown: (_) => ref.read(keySequenceProvider.notifier).cancel(),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => sequenceKey(event),
      child: child,
    ),
  );
}
