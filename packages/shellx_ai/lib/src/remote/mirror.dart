import 'package:shellx_acp/shellx_acp.dart';

import 'listing.dart';
import 'wire.dart';

/// One conversation item as the phone holds it (V2-2 D5): built from the
/// desktop's records, replaced (never changed) when the desktop sends a
/// newer [rev], so a view keys its widget on `(index, rev)`.
sealed class MirrorItem with Redacted {
  const MirrorItem(this.index, this.rev, this.turn);

  final int index;

  /// The desktop item's `rev`; -1 while a long text is only partly here (its
  /// [AiHave] then makes the desktop send the text again).
  final int rev;
  final int turn;
}

enum MirrorTextKind { user, agent, thought }

final class MirrorText extends MirrorItem {
  const MirrorText(
    super.index,
    super.rev,
    super.turn,
    this.kind,
    this.text, {
    this.fullLength,
    this.fromPhone = false,
  });

  final MirrorTextKind kind;
  final String text;

  /// Set when an earlier page brought only the start of a long text: its
  /// whole length (the rest is read on the computer).
  final int? fullLength;

  /// V2-2b B24: a user's prompt written on a phone (`src`), not at the
  /// computer.
  final bool fromPhone;
}

/// What happened to a tool call's permission request.
enum MirrorPermissionState { waiting, answered, cancelled }

/// Tool output: its first and last lines when it was long.
final class MirrorOutput with Redacted {
  const MirrorOutput({
    required this.head,
    this.tail = '',
    this.lines = 0,
    this.cut = false,
  });

  final String head;
  final String tail;
  final int lines;

  /// The middle was left on the computer ([lines] in all).
  final bool cut;
}

/// The changed region of one file (V2-2 D6); [oldText] null: a new file.
final class MirrorDiff with Redacted {
  const MirrorDiff({
    required this.path,
    required this.newText,
    this.oldText,
    this.plus = 0,
    this.minus = 0,
    this.cut = false,
  });

  final String path;
  final String? oldText;
  final String newText;
  final int plus;
  final int minus;
  final bool cut;
}

final class MirrorTool extends MirrorItem {
  const MirrorTool(
    super.index,
    super.rev,
    super.turn, {
    required this.toolCallId,
    this.kind,
    this.title,
    this.status,
    this.end,
    this.startedAt,
    this.endedAt,
    this.permission,
    this.answerKind,
    this.answerName,
    this.locations = const [],
    this.output,
    this.diffs = const [],
    this.moreDiffs = 0,
    this.input,
  });

  final String toolCallId;
  final ToolKind? kind;
  final String? title;
  final ToolCallStatus? status;

  /// `completed`, `failed` or `stopped` once it ended.
  final String? end;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final MirrorPermissionState? permission;
  final PermissionKind? answerKind;
  final String? answerName;
  final List<ToolLocation> locations;
  final MirrorOutput? output;
  final List<MirrorDiff> diffs;
  final int moreDiffs;

  /// The call's input as JSON text (`other` tools only).
  final String? input;
}

final class MirrorAsk extends MirrorItem {
  const MirrorAsk(
    super.index,
    super.rev,
    super.turn, {
    required this.id,
    required this.status,
    this.request,
  });

  final int id;

  /// `open`, `accepted`, `declined`, `cancelled`, `auto_declined`,
  /// `completed` (or a newer word).
  final String status;

  /// Null when the form was too big to send: answered on the computer.
  final ElicitationRequest? request;

  bool get open => status == 'open';
}

final class MirrorTurnEnd extends MirrorItem {
  const MirrorTurnEnd(
    super.index,
    super.rev,
    super.turn, {
    required this.outcome,
    required this.elapsed,
    this.stopReason,
    this.error,
    this.files,
    this.plus = 0,
    this.minus = 0,
  });

  /// `finished`, `cancelled`, `interrupted`, `failed`.
  final String outcome;
  final Duration elapsed;
  final String? stopReason;
  final String? error;

  /// Files the turn changed; null when undo was off (not counted).
  final int? files;
  final int plus;
  final int minus;
}

final class MirrorNotice extends MirrorItem {
  const MirrorNotice(
    super.index,
    super.rev,
    super.turn, {
    required this.kind,
    this.args = const {},
    this.resolved = false,
  });

  /// `login`, `node`, `not_installed`, `missing`, `exited`, `invalid`,
  /// `start_failed`, `cannot_resume`, `folder_missing`, `undo_off`.
  final String kind;
  final Map<String, Object?> args;
  final bool resolved;
}

/// An item kind this version does not know (a newer desktop's), or `big`:
/// a card too large to send, read on the computer.
final class MirrorUnknown extends MirrorItem {
  const MirrorUnknown(super.index, super.rev, super.turn, this.kind);

  final String? kind;
}

final class MirrorTurn with Redacted {
  const MirrorTurn({
    required this.index,
    required this.startedAt,
    this.stopping = false,
    this.canForceStop = false,
  });

  final int index;
  final DateTime startedAt;
  final bool stopping;
  final bool canForceStop;
}

final class MirrorPermission with Redacted {
  const MirrorPermission({
    required this.id,
    required this.title,
    required this.options,
    this.item,
    this.more = 0,
  });

  final int id;

  /// The tool card it belongs to (index), when the phone holds it.
  final int? item;
  final String title;
  final List<PermissionOption> options;

  /// Requests waiting after this one.
  final int more;
}

final class MirrorAskRef with Redacted {
  const MirrorAskRef({required this.id, this.item, this.more = 0});

  final int id;
  final int? item;
  final int more;
}

final class MirrorQueued with Redacted {
  const MirrorQueued(this.id, this.text);

  final int id;
  final String text;
}

/// The session's header (V2-2 §4.5).
final class MirrorHead with Redacted {
  const MirrorHead({
    required this.phase,
    required this.agentId,
    required this.agentName,
    this.title,
    this.cwd,
    this.turn,
    this.permission,
    this.ask,
    this.queue = const [],
    this.usage,
    this.plan = const [],
    this.modeId,
    this.modeName,
    this.unavailable,
  });

  /// `stopped`, `starting`, `needsAuth`, `ready`, `running`, `failed`.
  final String phase;
  final String agentId;
  final String agentName;
  final String? title;
  final String? cwd;
  final MirrorTurn? turn;
  final MirrorPermission? permission;
  final MirrorAskRef? ask;
  final List<MirrorQueued> queue;
  final Usage? usage;
  final List<PlanEntry> plan;
  final String? modeId;
  final String? modeName;

  /// The session cannot run now ([AiRemoteState.noFolder] or
  /// [AiRemoteState.agentOff]): set up on the computer.
  final AiRemoteState? unavailable;

  bool get running => turn != null;

  /// A prompt can be sent or queued now (V2-1 D16).
  bool get canSend =>
      unavailable == null &&
      phase != 'needsAuth' &&
      phase != 'failed' &&
      queue.length < 5;

  static MirrorHead fromJson(Map<String, Object?> j) {
    final turn = jMap(j, 'turn');
    final permission = jMap(j, 'perm');
    final ask = jMap(j, 'ask');
    final usage = jMap(j, 'usage');
    final mode = jMap(j, 'mode');
    final unavailable = jString(j, 'unavailable');
    return MirrorHead(
      phase: jString(j, 'phase') ?? 'stopped',
      agentId: jString(j, 'agent') ?? '',
      agentName: jString(j, 'name') ?? '',
      title: jString(j, 'title'),
      cwd: jString(j, 'cwd'),
      turn: turn == null
          ? null
          : MirrorTurn(
              index: jInt(turn, 'n') ?? 0,
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                jInt(turn, 't0') ?? 0,
              ),
              stopping: jBool(turn, 'stopping'),
              canForceStop: jBool(turn, 'force'),
            ),
      permission: permission == null || jInt(permission, 'id') == null
          ? null
          : MirrorPermission(
              id: jInt(permission, 'id')!,
              item: jInt(permission, 'item'),
              title: jString(permission, 'title') ?? '',
              options: [
                for (final o in jMaps(permission, 'options'))
                  if (jString(o, 'id') case final id?)
                    PermissionOption(
                      optionId: id,
                      name: jString(o, 'name') ?? '',
                      kind: PermissionKind.parse(jString(o, 'kind')),
                    ),
              ],
              more: jInt(permission, 'more') ?? 0,
            ),
      ask: ask == null || jInt(ask, 'id') == null
          ? null
          : MirrorAskRef(
              id: jInt(ask, 'id')!,
              item: jInt(ask, 'item'),
              more: jInt(ask, 'more') ?? 0,
            ),
      queue: [
        for (final q in jMaps(j, 'queue'))
          if (jInt(q, 'id') case final id?)
            MirrorQueued(id, jString(q, 'text') ?? ''),
      ],
      usage: usage == null
          ? null
          : Usage(
              used: jInt(usage, 'used') ?? 0,
              size: jInt(usage, 'size') ?? 0,
            ),
      plan: [
        for (final e in jMaps(j, 'plan'))
          PlanEntry(
            content: jString(e, 'text') ?? '',
            status: PlanStatus.parse(jString(e, 'st')),
          ),
      ],
      modeId: mode == null ? null : jString(mode, 'id'),
      modeName: mode == null ? null : jString(mode, 'name'),
      unavailable: unavailable == null
          ? null
          : AiRemoteState.parse(unavailable),
    );
  }
}

/// What a phone holds of a session, sent with `ai.attach` so a re-attach
/// only brings what changed (V2-2 D5).
final class AiHave with Redacted {
  const AiHave({
    required this.generation,
    required this.from,
    required this.revs,
  });

  final int generation;
  final int from;

  /// The rev of each held item, from index [from] on.
  final List<int> revs;

  Map<String, Object?> toJson() => {
    'g': generation,
    'from': from,
    'revs': revs,
  };

  static AiHave? fromJson(Map<String, Object?>? j) {
    if (j == null) return null;
    final g = jInt(j, 'g');
    final from = jInt(j, 'from');
    if (g == null || from == null || from < 0) return null;
    return AiHave(generation: g, from: from, revs: jInts(j, 'revs'));
  }
}

/// The phone's copy of one AI session (V2-2 D5): the header and a window of
/// the conversation, `[from, end)`, fed by the desktop's bodies in order.
final class AiMirror with Redacted {
  int _generation = -1;
  int _from = 0;
  int _count = 0;
  bool _hasEarlier = false;
  MirrorHead? _head;
  final List<MirrorItem> _items = [];
  final Set<int> _changed = {};
  int _version = 0;

  int get generation => _generation;

  /// The first index held.
  int get from => _from;

  /// One past the last index held.
  int get end => _from + _items.length;

  /// Items on the desktop when the last body was made.
  int get count => _count;

  /// Older items exist on the desktop ("Tải thêm").
  bool get hasEarlier => _hasEarlier;
  MirrorHead? get head => _head;

  /// The held items, oldest first.
  List<MirrorItem> get items => List.unmodifiable(_items);

  /// Indices the last [apply] added or replaced.
  Set<int> get changed => Set.unmodifiable(_changed);

  /// Goes up on every [apply] that changed something.
  int get version => _version;

  MirrorItem? at(int index) {
    final i = index - _from;
    return i < 0 || i >= _items.length ? null : _items[i];
  }

  AiHave get have => AiHave(
    generation: _generation,
    from: _from,
    revs: [for (final item in _items) item.rev],
  );

  /// Forgets everything (the session closed, or a resync).
  void clear() {
    _generation = -1;
    _from = 0;
    _count = 0;
    _hasEarlier = false;
    _head = null;
    _items.clear();
    _changed.clear();
    _version++;
  }

  /// Applies one body ([snapshot]: the first after an attach). False when
  /// it does not fit what is held (a record past the end, a text piece
  /// that does not continue the text): the caller attaches again.
  bool apply(Map<String, Object?> body, {required bool snapshot}) {
    _changed.clear();
    if (snapshot) {
      final g = jInt(body, 'g') ?? 0;
      final from = jInt(body, 'from') ?? 0;
      if (jBool(body, 'reset') || g != _generation || from != _from) {
        _items.clear();
        _from = from;
      }
      _generation = g;
      _hasEarlier = jBool(body, 'more');
    }
    _count = jInt(body, 'n') ?? _count;
    final head = jMap(body, 'head');
    if (head != null) _head = MirrorHead.fromJson(head);
    final records = jMaps(body, 'items').toList();
    var ok = true;
    if (jBool(body, 'older')) {
      ok = _prepend(records);
      _hasEarlier = jBool(body, 'more');
    } else {
      for (final r in records) {
        if (!_put(r)) {
          ok = false;
          break;
        }
      }
    }
    _version++;
    return ok;
  }

  bool _prepend(List<Map<String, Object?>> records) {
    final page = <MirrorItem>[];
    for (final r in records) {
      final item = _parse(r, null);
      if (item == null) return false;
      page.add(item);
    }
    page.sort((a, b) => a.index.compareTo(b.index));
    for (var i = 0; i < page.length; i++) {
      if (page[i].index != _from - page.length + i) return false;
    }
    _items.insertAll(0, page);
    _from -= page.length;
    _changed.addAll(page.map((p) => p.index));
    return true;
  }

  bool _put(Map<String, Object?> r) {
    final index = jInt(r, 'i');
    if (index == null || index < _from) return index != null; // not held
    if (index > end) return false;
    final current = index < end ? _items[index - _from] : null;
    final item = _parse(r, current);
    if (item == null) return false;
    if (current == null) {
      _items.add(item);
    } else {
      _items[index - _from] = item;
    }
    _changed.add(index);
    return true;
  }

  /// Null when a text piece does not continue [current].
  static MirrorItem? _parse(Map<String, Object?> r, MirrorItem? current) {
    final index = jInt(r, 'i') ?? -1;
    final rev = jInt(r, 'r') ?? 0;
    final turn = jInt(r, 'turn') ?? 0;
    final kind = jString(r, 'k');
    DateTime? time(String key) {
      final ms = jInt(r, key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    switch (kind) {
      case 'user' || 'agent' || 'thought':
        final at = jInt(r, 'at') ?? 0;
        final add = jString(r, 'add') ?? '';
        final before = current is MirrorText ? current.text : '';
        if (at != 0 && at != before.length) return null;
        return MirrorText(
          index,
          rev,
          turn,
          MirrorTextKind.values.byName(kind!),
          at == 0 ? add : before + add,
          fullLength: jInt(r, 'clip'),
          fromPhone: jString(r, 'src') == 'phone',
        );
      case 'tool':
        final out = jMap(r, 'out');
        final ans = jMap(r, 'ans');
        return MirrorTool(
          index,
          rev,
          turn,
          toolCallId: jString(r, 'id') ?? '',
          kind: ToolKind.parse(jString(r, 'tk')),
          title: jString(r, 'title'),
          status: ToolCallStatus.parse(jString(r, 'st')),
          end: jString(r, 'end'),
          startedAt: time('t0'),
          endedAt: time('t1'),
          permission: switch (jString(r, 'perm')) {
            'waiting' => MirrorPermissionState.waiting,
            'answered' => MirrorPermissionState.answered,
            'cancelled' => MirrorPermissionState.cancelled,
            _ => null,
          },
          answerKind: ans == null
              ? null
              : PermissionKind.parse(jString(ans, 'kind')),
          answerName: ans == null ? null : jString(ans, 'name'),
          locations: [
            for (final l in jMaps(r, 'loc'))
              ToolLocation(jString(l, 'path') ?? '', jInt(l, 'line')),
          ],
          output: out == null
              ? null
              : MirrorOutput(
                  head: jString(out, 'head') ?? '',
                  tail: jString(out, 'tail') ?? '',
                  lines: jInt(out, 'lines') ?? 0,
                  cut: jBool(out, 'cut'),
                ),
          diffs: [
            for (final d in jMaps(r, 'diffs'))
              MirrorDiff(
                path: jString(d, 'path') ?? '',
                oldText: jBool(d, 'created') ? null : jString(d, 'old') ?? '',
                newText: jString(d, 'new') ?? '',
                plus: jInt(d, 'plus') ?? 0,
                minus: jInt(d, 'minus') ?? 0,
                cut: jBool(d, 'cut'),
              ),
          ],
          moreDiffs: jInt(r, 'more_diffs') ?? 0,
          input: jString(r, 'input'),
        );
      case 'ask':
        final req = jMap(r, 'req');
        return MirrorAsk(
          index,
          rev,
          turn,
          id: jInt(r, 'id') ?? -1,
          status: jString(r, 'st') ?? 'open',
          request: req == null ? null : ElicitationRequest.fromJson(req),
        );
      case 'end':
        return MirrorTurnEnd(
          index,
          rev,
          turn,
          outcome: jString(r, 'outcome') ?? 'finished',
          elapsed: Duration(milliseconds: jInt(r, 'ms') ?? 0),
          stopReason: jString(r, 'stop'),
          error: jString(r, 'error'),
          files: jInt(r, 'files'),
          plus: jInt(r, 'plus') ?? 0,
          minus: jInt(r, 'minus') ?? 0,
        );
      case 'notice':
        final n = jMap(r, 'n') ?? const {};
        return MirrorNotice(
          index,
          rev,
          turn,
          kind: jString(n, 'k') ?? '',
          args: n,
          resolved: jBool(r, 'resolved'),
        );
      default:
        return MirrorUnknown(index, rev, turn, kind);
    }
  }
}
