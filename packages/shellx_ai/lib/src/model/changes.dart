import 'package:shellx_acp/shellx_acp.dart';

enum ChangeKind { added, modified, deleted }

/// One file changed since a checkpoint (spec §4.4).
final class FileChange with Redacted {
  const FileChange({
    required this.path,
    required this.kind,
    this.added,
    this.removed,
  });

  /// Relative to the project, with `/` separators.
  final String path;
  final ChangeKind kind;

  /// Lines added and removed; null for a binary file.
  final int? added;
  final int? removed;

  bool get binary => added == null;
}

/// The project as it was before a turn (spec D12).
final class Checkpoint with Redacted {
  const Checkpoint({required this.commit, required this.tree});

  final String commit;
  final String tree;
}

/// Why undo is off for a project (spec §6, `aiNoUndo`).
enum UndoOff {
  noGit,
  noCommandLineTools,
  gitTooOld,
  tooManyFiles,
  tooSlow,
  failed,
}
