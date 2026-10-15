import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/timeline.dart';
import 'acp_out.dart';
import 'item_codec.dart' show itemText;
import 'mirror.dart';
import 'wire.dart';

/// V2-2b B16, R14: the most bytes one slice of a full item takes once escaped
/// for JSON. With the slice's envelope a body stays far below [kAiBodyBytes]
/// whatever the text holds (quotes, control characters, lone surrogates).
const int kAiSliceBytes = 36 * 1024;

/// V2-2b B16: the largest full item a phone loads, in UTF-8 bytes of its
/// JSON (about 60 slices); a bigger one is read on the computer (`too_big`).
const int kAiFullItemBytes = 2 * 1024 * 1024;

/// A line of tool output in a full item, cut as the desktop's card cuts it.
const int kAiFullLineChars = 2000;

/// The largest side of a diff in a full item, in UTF-8 bytes; a bigger file
/// is named, and read on the computer.
const int kAiFullDiffBytes = 1024 * 1024;

/// V2-2b B16: item [item] in full as JSON text — what the phone's "Xem đủ"
/// shows: a text whole; a tool call's output (each line cut at
/// [kAiFullLineChars]), every diff whole (a side over [kAiFullDiffBytes] only
/// named, `big`) and, for a call of kind `other`, its input; a question's
/// whole form. Null for an item that holds nothing more than the mirror
/// shows (a turn's end, a notice).
String? aiFullItemJson(TimelineItem item) {
  final Map<String, Object?> view;
  switch (item) {
    case UserItem() || StreamedTextItem():
      view = {
        'k': switch (item) {
          UserItem() => 'user',
          ThoughtItem() => 'thought',
          _ => 'agent',
        },
        'text': itemText(item) ?? '',
      };
    case ToolItem():
      view = _tool(item);
    case AskItem():
      view = {'k': 'ask', 'req': elicitationToJson(item.request)};
    case TurnEndItem() || NoticeItem():
      return null;
  }
  return jsonEncode(view);
}

Map<String, Object?> _tool(ToolItem t) {
  final f = t.fields;
  final texts = <String>[];
  final diffs = <Map<String, Object?>>[];
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
        diffs.add(_diff(c));
      case ToolTerminal() || ToolContentOther():
        break;
    }
  }
  String? input;
  final raw = f.rawInput;
  if (raw != null && (f.kind == null || f.kind == ToolKind.other)) {
    try {
      input = const JsonEncoder.withIndent('  ').convert(raw);
    } on Object {
      input = null; // Not JSON: not shown, as in the mirror.
    }
  }
  return {
    'k': 'tool',
    'title': ?f.title,
    if (texts.isNotEmpty) 'out': _cutLines(texts.join('\n')),
    if (diffs.isNotEmpty) 'diffs': diffs,
    'input': ?input,
  };
}

Map<String, Object?> _diff(ToolDiff d) {
  final old = d.oldText;
  if (utf8Length(d.newText) > kAiFullDiffBytes ||
      (old != null && utf8Length(old) > kAiFullDiffBytes)) {
    return {'path': d.path, 'big': true};
  }
  return {
    'path': d.path,
    'old': ?old,
    'new': d.newText,
    if (old == null) 'created': true,
  };
}

/// [text] with each line cut at [kAiFullLineChars] characters ("…" after).
String _cutLines(String text) {
  if (!text.split('\n').any((l) => l.length > kAiFullLineChars)) return text;
  return [
    for (final line in text.split('\n'))
      if (line.length <= kAiFullLineChars)
        line
      else
        '${line.substring(0, _safeEnd(line, kAiFullLineChars))}…',
  ].join('\n');
}

/// [end], one less when it would split a surrogate pair.
int _safeEnd(String s, int end) {
  final c = s.codeUnitAt(end - 1);
  return c >= 0xD800 && c <= 0xDBFF ? end - 1 : end;
}

/// V2-2b B16, R14: where the slices of [text] end (exclusive offsets, the
/// last one `text.length`): each slice is at most [maxBytes] once escaped
/// for JSON, so its body fits a message whatever the text holds, and none
/// ends inside a surrogate pair. An empty text is one empty slice.
List<int> aiSliceEnds(String text, {int maxBytes = kAiSliceBytes}) {
  final ends = <int>[];
  var start = 0;
  var size = 0;
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    var units = 1;
    final int cost;
    if (c == 0x22 || c == 0x5C) {
      cost = 2; // \" \\
    } else if (c < 0x20) {
      // \b \t \n \f \r, else \u00XX
      cost = c == 0x08 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D
          ? 2
          : 6;
    } else if (c < 0x80) {
      cost = 1;
    } else if (c < 0x800) {
      cost = 2;
    } else if (c >= 0xD800 &&
        c <= 0xDBFF &&
        i + 1 < text.length &&
        (text.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
      cost = 4;
      units = 2;
    } else if (c >= 0xD800 && c <= 0xDFFF) {
      cost = 6; // a lone surrogate: \uXXXX at most
    } else {
      cost = 3;
    }
    if (size + cost > maxBytes && i > start) {
      ends.add(i);
      start = i;
      size = 0;
    }
    size += cost;
    i += units;
  }
  ends.add(text.length);
  return ends;
}

/// V2-2b B16: an item in full as the phone's viewer shows it (what
/// [aiFullItemJson] made, joined from its slices).
final class AiFullView with Redacted {
  const AiFullView({
    required this.kind,
    this.title,
    this.text,
    this.output,
    this.diffs = const [],
    this.bigDiffs = const [],
    this.input,
    this.request,
  });

  /// `user`, `agent`, `thought`, `tool`, `ask`, or a newer computer's word.
  final String kind;
  final String? title;

  /// A text item's whole text.
  final String? text;

  /// A tool call's output; each line at most [kAiFullLineChars] characters.
  final String? output;

  /// Every diff of the call, whole ([MirrorDiff.oldText] null: a new file;
  /// `plus`, `minus` and `cut` unset).
  final List<MirrorDiff> diffs;

  /// The paths of the files too big to load: read on the computer.
  final List<String> bigDiffs;

  /// The call's input as indented JSON (calls of kind `other`).
  final String? input;

  /// A question's whole form.
  final ElicitationRequest? request;

  /// Null without a kind.
  static AiFullView? fromJson(Map<String, Object?> j) {
    final kind = jString(j, 'k');
    if (kind == null) return null;
    final diffs = jMaps(j, 'diffs').toList();
    final req = jMap(j, 'req');
    return AiFullView(
      kind: kind,
      title: jString(j, 'title'),
      text: jString(j, 'text'),
      output: jString(j, 'out'),
      diffs: [
        for (final d in diffs)
          if (!jBool(d, 'big'))
            MirrorDiff(
              path: jString(d, 'path') ?? '',
              oldText: jBool(d, 'created') ? null : jString(d, 'old') ?? '',
              newText: jString(d, 'new') ?? '',
            ),
      ],
      bigDiffs: [
        for (final d in diffs)
          if (jBool(d, 'big')) jString(d, 'path') ?? '',
      ],
      input: jString(j, 'input'),
      request: req == null ? null : ElicitationRequest.fromJson(req),
    );
  }
}
