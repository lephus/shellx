import 'dart:convert';
import 'dart:math';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/notices.dart';
import '../model/session_state.dart';
import '../model/timeline.dart';
import 'acp_out.dart';
import 'undo_view.dart';
import 'wire.dart';

/// The text of a text item (user prompt, agent text, thought); null for
/// any other item.
String? itemText(TimelineItem item) => switch (item) {
  UserItem() => item.text,
  StreamedTextItem() => item.text,
  _ => null,
};

/// A text record of item [index]: its text from char [from] (UTF-16 code
/// units), at most [maxBytes] of UTF-8. Returns the record and where the
/// piece ends (= the text's length when all of it went).
///
/// While the text goes on in a later piece the record has `r` = -1, not the
/// item's rev: the phone does not hold the item yet, so a channel lost here
/// must not make its [AiHave] claim it, or the rest would never come. With
/// [clip] the piece is all the phone gets of the text (an older page): it
/// has the item's rev, and `clip` = the whole length when the text goes on.
(Map<String, Object?>, int) encodeTextPiece(
  TimelineItem item,
  int index, {
  int from = 0,
  int maxBytes = kAiTextChunkBytes,
  bool clip = false,
}) {
  final text = itemText(item) ?? '';
  final start = min(from, text.length);
  final end = utf8Cut(text, maxBytes, from: start);
  final goesOn = end < text.length;
  // V2-2b B12: how many images went with a user's message (the phone shows
  // "2 ảnh"; the images themselves stay on the computer).
  final images = item is UserItem
      ? item.blocks.whereType<ImageBlock>().length
      : 0;
  return (
    {
      'i': index,
      'r': goesOn && !clip ? -1 : item.rev,
      'k': switch (item) {
        UserItem() => 'user',
        ThoughtItem() => 'thought',
        _ => 'agent',
      },
      'turn': item.turn,
      'at': start,
      'add': text.substring(start, end),
      if (goesOn && clip) 'clip': text.length,
      // V2-2b B24: a phone's prompt says so (an older phone skips the key).
      if (item is UserItem && item.source == PromptSource.phone) 'src': 'phone',
      if (images > 0) 'img': images,
    },
    end,
  );
}

/// A text piece of item [index] from char [from] as JSON, within
/// [kAiRecordBytes] once escaped (newlines and quotes grow in JSON). See
/// [encodeTextPiece] for [clip].
(String, int) encodeTextRecord(
  TimelineItem item,
  int index, {
  int from = 0,
  bool clip = false,
}) {
  var maxBytes = kAiTextChunkBytes;
  while (true) {
    final (piece, end) = encodeTextPiece(
      item,
      index,
      from: from,
      maxBytes: maxBytes,
      clip: clip,
    );
    final json = jsonEncode(piece);
    if (utf8Length(json) <= kAiRecordBytes || maxBytes <= 256) {
      return (json, end);
    }
    maxBytes ~/= 2;
  }
}

/// Item [index] as JSON within [kAiRecordBytes]: a tool card is cut harder
/// until it fits, else it becomes a `big` stub ("xem trên máy tính").
String encodeItemRecord(TimelineItem item, int index) {
  if (item is ToolItem) {
    for (final scale in const [1, 2, 4, 8]) {
      final json = jsonEncode({
        'i': index,
        'r': item.rev,
        'turn': item.turn,
        ..._tool(item, scale: scale),
      });
      if (utf8Length(json) <= kAiRecordBytes) return json;
    }
    return jsonEncode({
      'i': index,
      'r': item.rev,
      'turn': item.turn,
      'k': 'big',
    });
  }
  final json = jsonEncode(encodeItem(item, index));
  if (utf8Length(json) <= kAiRecordBytes) return json;
  return jsonEncode({'i': index, 'r': item.rev, 'turn': item.turn, 'k': 'big'});
}

/// Item [index] as the phone gets it (V2-2 §4.4): tool output and diffs are
/// cut to what a phone shows; a text item is its first piece (see
/// [encodeTextPiece]).
Map<String, Object?> encodeItem(TimelineItem item, int index) {
  final head = {'i': index, 'r': item.rev, 'turn': item.turn};
  return switch (item) {
    UserItem() || StreamedTextItem() => encodeTextPiece(item, index).$1,
    ToolItem() => {...head, ..._tool(item)},
    AskItem() => {...head, ..._ask(item)},
    TurnEndItem() => {...head, ..._turnEnd(item)},
    NoticeItem() => {
      ...head,
      'k': 'notice',
      'n': _notice(item.notice),
      if (item.resolved) 'resolved': true,
    },
  };
}

/// [scale] divides every cut (a card still too big is cut harder).
Map<String, Object?> _tool(ToolItem t, {int scale = 1}) {
  final f = t.fields;
  final answer = t.permissionAnswer;
  final texts = <String>[];
  final diffs = <ToolDiff>[];
  for (final c in f.content ?? const <ToolContent>[]) {
    switch (c) {
      case ToolContentBlock(:final block):
        final text = switch (block) {
          TextBlock(:final text) => text,
          ResourceLinkBlock(:final name) => name,
          ResourceBlock(:final text) => text ?? '',
          _ => '',
        };
        if (text.isNotEmpty) texts.add(plainText(text));
      case ToolDiff():
        diffs.add(c);
      case ToolTerminal() || ToolContentOther():
        break;
    }
  }
  final input = f.rawInput;
  String? inputText;
  if (input != null && (f.kind == null || f.kind == ToolKind.other)) {
    try {
      inputText = clipText(jsonEncode(input), kAiInputBytes ~/ scale);
    } on Object {
      inputText = null; // Not JSON: not shown.
    }
  }
  return {
    'k': 'tool',
    'id': t.toolCallId,
    if (f.kind != null) 'tk': f.kind!.wire,
    if (f.title != null) 'title': clipText(f.title!, 600),
    if (f.status != null) 'st': f.status!.wire,
    if (t.end != null) 'end': t.end!.name,
    't0': t.startedAt.millisecondsSinceEpoch,
    if (t.endedAt != null) 't1': t.endedAt!.millisecondsSinceEpoch,
    if (t.awaitingPermission)
      'perm': 'waiting'
    else if (answer != null)
      'perm': 'answered'
    else if (t.permissionCancelled)
      'perm': 'cancelled',
    if (answer != null)
      'ans': {'kind': answer.kind.wire, 'name': clipText(answer.name, 300)},
    if (f.locations case final locations? when locations.isNotEmpty)
      'loc': [
        for (final l in locations.take(5))
          {'path': clipText(l.path, 600), 'line': ?l.line},
      ],
    if (texts.isNotEmpty)
      'out': _output(texts.join('\n'), kAiOutputBytes ~/ scale),
    if (diffs.isNotEmpty)
      'diffs': [
        for (final d in diffs.take(kAiMaxDiffs))
          _diff(d, kAiDiffSideBytes ~/ scale),
      ],
    if (diffs.length > kAiMaxDiffs) 'more_diffs': diffs.length - kAiMaxDiffs,
    'input': ?inputText,
  };
}

Map<String, Object?> _output(String text, int side) {
  final lines = '\n'.allMatches(text).length + 1;
  if (utf8Length(text) <= 2 * side) {
    return {'head': text, 'lines': lines};
  }
  return {
    'head': headLines(text, side),
    'tail': tailLines(text, side),
    'lines': lines,
    'cut': true,
  };
}

/// The changed region of [d] with [kAiDiffContext] lines around it: the
/// lines both sides share at the start and at the end are dropped (V2-2
/// D6). A new file keeps its first lines.
Map<String, Object?> _diff(ToolDiff d, int side) {
  final newLines = const LineSplitter().convert(d.newText);
  final path = clipText(d.path, 600);
  final old = d.oldText;
  if (old == null) {
    final text = headLines(d.newText, side);
    return {
      'path': path,
      'new': text,
      'created': true,
      'plus': newLines.length,
      'minus': 0,
      if (text.length < d.newText.length) 'cut': true,
    };
  }
  final oldLines = const LineSplitter().convert(old);
  var start = 0;
  while (start < oldLines.length &&
      start < newLines.length &&
      oldLines[start] == newLines[start]) {
    start++;
  }
  var endOld = oldLines.length;
  var endNew = newLines.length;
  while (endOld > start &&
      endNew > start &&
      oldLines[endOld - 1] == newLines[endNew - 1]) {
    endOld--;
    endNew--;
  }
  final from = max(0, start - kAiDiffContext);
  final oldRegion = oldLines
      .sublist(from, min(oldLines.length, endOld + kAiDiffContext))
      .join('\n');
  final newRegion = newLines
      .sublist(from, min(newLines.length, endNew + kAiDiffContext))
      .join('\n');
  final oldCut = headLines(oldRegion, side);
  final newCut = headLines(newRegion, side);
  return {
    'path': path,
    'old': oldCut,
    'new': newCut,
    'plus': endNew - start,
    'minus': endOld - start,
    if (oldCut.length < oldRegion.length || newCut.length < newRegion.length)
      'cut': true,
  };
}

Map<String, Object?> _ask(AskItem a) {
  final response = a.response;
  final status = a.autoDeclined
      ? 'auto_declined'
      : switch (response) {
          ElicitAccept() => 'accepted',
          ElicitDecline() => 'declined',
          ElicitCancel() => 'cancelled',
          null => a.completed ? 'completed' : 'open',
        };
  final request = elicitationToJson(a.request);
  final fits = utf8Length(jsonEncode(request)) <= kAiAskBytes;
  return {
    'k': 'ask',
    'id': a.id,
    'st': status,
    if (fits) 'req': request else 'big': true,
  };
}

Map<String, Object?> _turnEnd(TurnEndItem e) {
  final changes = e.changes;
  return {
    'k': 'end',
    'outcome': e.outcome.name,
    'ms': e.elapsed.inMilliseconds,
    if (e.stopReason != null) 'stop': e.stopReason!.wire,
    if (e.error != null) 'error': clipText(e.error!, 1000),
    if (changes != null) ...{
      'files': changes.length,
      'plus': changes.fold<int>(0, (n, c) => n + (c.added ?? 0)),
      'minus': changes.fold<int>(0, (n, c) => n + (c.removed ?? 0)),
    },
  };
}

Map<String, Object?> _notice(AiNotice n) => switch (n) {
  LoginNeeded(:final methods) => {
    'k': 'login',
    'methods': [for (final m in methods.take(5)) clipText(m.name, 200)],
  },
  NodeMissing(:final required, :final found) => {
    'k': 'node',
    'required': required,
    'found': ?found,
  },
  AgentNotInstalled() => {'k': 'not_installed'},
  AgentMissing() => {'k': 'missing'},
  AgentExited(:final exitCode) => {'k': 'exited', 'code': exitCode},
  AgentOutputInvalid() => {'k': 'invalid'},
  StartFailed(:final reason) => {'k': 'start_failed', 'reason': reason.name},
  CannotResume() => {'k': 'cannot_resume'},
  FolderMissing() => {'k': 'folder_missing'},
  UndoUnavailable(:final reason, :final turnOnly) => {
    'k': 'undo_off',
    'reason': reason.name,
    if (turnOnly) 'turn_only': true,
  },
};

/// The session's header for the phone (V2-2 §4.5). [indexOf] gives a
/// timeline item's index (the card a permission or question belongs to).
Map<String, Object?> encodeHead(
  AiSessionState s,
  int Function(TimelineItem item) indexOf,
) {
  final turn = s.turn;
  final permission = s.currentPermission;
  final ask = s.currentAsk;
  final usage = s.usage;
  final mode = _mode(s);
  return {
    'phase': s.phase.name,
    if (s.label case final label?) 'title': clipText(label, 400),
    'agent': s.agentId,
    'name': s.agentName,
    'cwd': s.cwd,
    if (turn != null)
      'turn': {
        'n': turn.index,
        't0': turn.startedAt.millisecondsSinceEpoch,
        if (turn.cancelRequested) 'stopping': true,
        if (turn.canForceStop) 'force': true,
      },
    if (permission != null)
      'perm': {
        'id': permission.id,
        'item': indexOf(permission.item),
        'title': clipText(permission.title, 600),
        'options': [
          for (final o in permission.request.options)
            {
              'id': o.optionId,
              'name': clipText(o.name, 300),
              'kind': o.kind.wire,
            },
        ],
        if (s.permissions.length > 1) 'more': s.permissions.length - 1,
      },
    if (ask != null)
      'ask': {
        'id': ask.id,
        'item': indexOf(ask.item),
        if (s.asks.length > 1) 'more': s.asks.length - 1,
      },
    if (s.queue.isNotEmpty)
      'queue': [
        for (final q in s.queue) {'id': q.id, 'text': clipText(q.text, 400)},
      ],
    if (usage != null) 'usage': {'used': usage.used, 'size': usage.size},
    if (s.plan.isNotEmpty)
      'plan': [
        for (final e in s.plan.take(30))
          {'text': clipText(e.content, 600), 'st': e.status.wire},
      ],
    'mode': ?mode,
    // V2-2b §4.2: the agent's own session id (a phone finds the session
    // again after the computer restarted ShellX, B22), the model, whether
    // the agent lists its earlier sessions (B17), whether undo works (B19).
    if (s.sessionId case final acp?) 'acp': clipText(acp, 200),
    'model': ?_model(s),
    if (s.capabilities.listSessions) 'hist': true,
    'undo': aiUndoIsOff(s) ? 'off' : 'on',
  };
}

/// V2-2b B11: the current model, by id and name — the choice of the option
/// in the `model` category; null when the agent offers none.
Map<String, Object?>? _model(AiSessionState s) {
  for (final o in s.configOptions ?? const <ConfigOption>[]) {
    if (o.category != 'model') continue;
    for (final c in o.choices) {
      if (c.value == o.currentValue) {
        return {'id': clipText(c.value, 200), 'name': clipText(c.name, 200)};
      }
    }
  }
  return null;
}

/// The current mode, by id and name: the phone words Claude's known ids
/// itself (V2-1 D11) and shows other agents' names as sent.
Map<String, Object?>? _mode(AiSessionState s) {
  for (final o in s.configOptions ?? const <ConfigOption>[]) {
    if (o.category != 'mode') continue;
    final value = o.currentValue;
    for (final c in o.choices) {
      if (c.value == value) {
        return {'id': c.value, 'name': clipText(c.name, 200)};
      }
    }
  }
  final modes = s.modes;
  if (modes == null) return null;
  for (final m in modes.available) {
    if (m.id == modes.currentModeId) {
      return {'id': m.id, 'name': clipText(m.name, 200)};
    }
  }
  return null;
}
