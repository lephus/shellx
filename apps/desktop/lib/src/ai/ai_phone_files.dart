import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/shellx_ai.dart' show AiSessionState;

import '../ui/ai/ai_changes_panel.dart' show aiLastEndedTurn;
import '../ui/ai/ai_completer.dart' show aiMatchFiles;
import 'ai_project_files.dart';

/// V2-2b B13, R18: the files of a session's folder a phone may name with
/// `@` — the project index the composer's `@` reads (V2-1 D16), read again
/// once a turn ended since, kept for at most [keep] folders. A turn's number
/// is its session's own (the composer keeps one index per pane): a read is
/// fresh only for the session that made it, and another session in the
/// folder reads it again (F37).
final class AiPhoneFileIndex {
  AiPhoneFileIndex(this._project);

  final AiProjectFiles _project;

  /// The folders whose index is kept at once.
  static const keep = 4;

  /// Per folder, the least recently used first: its index, the session that
  /// read it (weakly: a closed session is not kept alive for it), and the
  /// last turn that had ended in that session then.
  final _held =
      <
        String,
        ({
          WeakReference<AiSessionState> state,
          int? turn,
          Future<List<String>> files,
        })
      >{};

  /// The files of [state]'s folder (relative, `/` between their parts).
  Future<List<String>> files(AiSessionState state) {
    final cwd = state.cwd;
    final turn = aiLastEndedTurn(state);
    final held = _held.remove(cwd);
    final files =
        held != null && identical(held.state.target, state) && held.turn == turn
        ? held.files
        : _project.index(cwd).catchError((Object _) => const <String>[]);
    _held[cwd] = (state: WeakReference(state), turn: turn, files: files);
    if (_held.length > keep) _held.remove(_held.keys.first);
    return files;
  }

  /// The files of [state]'s folder matching [query], best first, as the
  /// composer's `@` offers them (eight at most).
  Future<List<String>> match(AiSessionState state, String query) async => [
    for (final hit in aiMatchFiles(await files(state), query)) hit.mention!,
  ];
}

/// The window's index for the phones' `@` (V2-2b B13).
final aiPhoneFileIndexProvider = Provider<AiPhoneFileIndex>(
  (ref) => AiPhoneFileIndex(ref.read(aiProjectFilesProvider)),
);
