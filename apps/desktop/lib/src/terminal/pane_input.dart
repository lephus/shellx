import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/window_focus.dart' show terminalFocusRequestProvider;
import 'clipboard_media.dart';
import 'pane_paste.dart';
import 'paste_image_store.dart';
import 'paste_sender.dart' show PasteOutcome;
import 'shell_escape.dart';
import 'terminal_tabs.dart';

/// What happened to a drop or an image paste (A10 D15–D17).
enum InputOutcome {
  sent,
  ssh,
  refusedName,
  tooMany,
  tooLarge,
  imageTooLarge,
  imageFailed,
  gone,
}

/// At most this many files go in with one drop or paste.
const int kMaxDroppedFiles = 100;

/// A10 D17: pane input that is not text. Every refusal is a toast.
final paneInputProvider = Provider<PaneInput>((ref) => PaneInput(ref));

class PaneInput {
  PaneInput(this._ref);
  final Ref _ref;

  PaneSession? _pane(int id) =>
      _ref.read(terminalTabsProvider).tabOfSession(id)?.panes[id];

  /// A pane of a server (SSH, or tmux on a server): its files are not ours.
  static bool isRemote(PaneSession pane) => pane.remote?.launch.host != null;

  void _notice(InputNoticeKind kind) =>
      _ref.read(terminalTabsProvider.notifier).showNotice(InputNotice(kind));

  /// Writes [paths], shell-escaped, into pane [paneId] as a paste (so a
  /// program that asked for bracketed paste gets them bracketed, and
  /// nothing runs): each followed by a space, no Enter. [focus] gives the
  /// pane the keyboard (a drop).
  Future<InputOutcome> insertPaths(
    int paneId,
    List<String> paths, {
    bool focus = false,
  }) async {
    final pane = _pane(paneId);
    if (pane == null || pane.exited || paths.isEmpty) return InputOutcome.gone;
    if (isRemote(pane)) {
      _notice(InputNoticeKind.dropSsh);
      return InputOutcome.ssh;
    }
    if (paths.length > kMaxDroppedFiles) {
      _notice(InputNoticeKind.dropTooMany);
      return InputOutcome.tooMany;
    }
    final String text;
    try {
      text = escapePaths(
        paths,
        shellFamilyOf(pane.shell, windows: Platform.isWindows),
      );
    } on FormatException {
      _notice(InputNoticeKind.dropRefused);
      return InputOutcome.refusedName;
    }
    if (focus) {
      _ref.read(terminalTabsProvider.notifier).focusPane(paneId);
      _ref.read(terminalFocusRequestProvider.notifier).request();
    }
    final outcome = await _ref
        .read(pasteSenderProvider)
        .send(
          paneId,
          text,
          PanePasteSink(
            () => _ref.read(terminalTabsProvider),
            paneId,
            pane.terminal,
          ),
        );
    if (outcome == PasteOutcome.tooLarge) {
      _ref
          .read(terminalTabsProvider.notifier)
          .showNotice(const PasteTooLargeNotice());
      return InputOutcome.tooLarge;
    }
    return InputOutcome.sent;
  }

  /// Saves the clipboard image [bytes] to a private temp file and pastes
  /// its path (A10 D15).
  Future<InputOutcome> pasteImage(int paneId, Uint8List bytes) async {
    final pane = _pane(paneId);
    if (pane == null || pane.exited) return InputOutcome.gone;
    if (isRemote(pane)) {
      _notice(InputNoticeKind.imageSsh);
      return InputOutcome.ssh;
    }
    final String path;
    try {
      path = await _ref.read(pasteImageStoreProvider).save(bytes);
    } on PasteImageTooLarge {
      _notice(InputNoticeKind.imageTooLarge);
      return InputOutcome.imageTooLarge;
    } on Object {
      _notice(InputNoticeKind.imageFailed);
      return InputOutcome.imageFailed;
    }
    return insertPaths(paneId, [path]);
  }
}
