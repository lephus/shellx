import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/session_state.dart';
import '../model/timeline.dart';
import 'item_codec.dart';
import 'mirror.dart';
import 'wire.dart';

/// One mirror message to send: `ai.snapshot` when [snapshot], else
/// `ai.update`; [seq] goes up by one per message of a subscription.
final class AiOutgoing with Redacted {
  const AiOutgoing(this.seq, this.body, {this.snapshot = false});

  final int seq;
  final Uint8List body;
  final bool snapshot;
}

/// What one phone has been sent of one session, and what to send next
/// (V2-2 D5): item records keyed by index and `rev`, text as appended
/// pieces, the header when it changed. Every body stays within
/// [kAiBodyBytes]; about [windowBytes] wait for an `ai.ack` at most. Pure
/// bookkeeping: the hub decides when to call it. Kept across re-attaches
/// of the same phone, so [AiOutgoing.seq] never goes back.
final class AiSubscription with Redacted {
  AiSubscription(
    this.state, {
    required this.generation,
    this.attachItems = kAiAttachItems,
    this.pageItems = kAiPageItems,
    this.windowBytes = kAiWindowBytes,
  });

  final AiSessionState state;

  /// Tells this state apart from another one of the same session (a new
  /// runtime): an [AiHave] of another generation is not used.
  final int generation;
  final int attachItems;
  final int pageItems;
  final int windowBytes;

  var _seq = 0;
  var _from = 0;

  /// The rev sent for each index from [_from] on; -1: the phone's copy is
  /// outdated or a text is still partial.
  final _revs = <int>[];

  /// Text items: how much of the text the phone has (UTF-16 units).
  final _textSent = <int, int>{};
  String? _head;
  var _version = -1;
  var _rest = false;
  final _inflight = <(int, int)>[];

  /// Bytes sent and not yet acknowledged.
  int get unackedBytes => _inflight.fold(0, (n, e) => n + e.$2);

  /// The window has room.
  bool get canSend => unackedBytes < windowBytes;

  /// Something changed since the last bodies, or a part is still to go.
  bool get dirty => state.version != _version || _rest;

  /// The first index the phone holds.
  int get from => _from;

  /// The bodies after an attach: one `ai.snapshot`, then `ai.update`s
  /// while the window allows (the rest goes with [delta]). [have] is used
  /// when it is of this [generation], holds something and is recent enough
  /// (at most twice [attachItems] new items since).
  List<AiOutgoing> attach(AiHave? have) {
    final items = state.timeline.items;
    final n = items.length;
    _revs.clear();
    _textSent.clear();
    _head = null;
    final reuse =
        have != null &&
        have.generation == generation &&
        have.revs.isNotEmpty &&
        have.from + have.revs.length <= n &&
        n - (have.from + have.revs.length) <= 2 * attachItems;
    if (reuse) {
      _from = have.from;
      for (var k = 0; k < have.revs.length; k++) {
        final item = items[_from + k];
        if (have.revs[k] == item.rev) {
          _revs.add(item.rev);
          final text = itemText(item);
          if (text != null) _textSent[_from + k] = text.length;
        } else {
          _revs.add(-1);
        }
      }
    } else {
      _from = max(0, n - attachItems);
    }
    return _produce(
      snapshot: {
        'g': generation,
        'from': _from,
        'reset': !reuse,
        'more': _from > 0,
      },
    );
  }

  /// What changed since the last bodies, within the window (at least one
  /// body when anything did). Empty when nothing changed.
  List<AiOutgoing> delta() => dirty ? _produce() : const [];

  /// The page before index [before] (it must be [from]): whole items, the
  /// newest body first, each one continuing the held window downwards. A
  /// text longer than one piece comes cut, with `clip` = its full length.
  List<AiOutgoing> earlier(int before) {
    if (before != _from || _from == 0) return const [];
    final items = state.timeline.items;
    final start = max(0, _from - pageItems);
    final records = <(String, int)>[];
    final revs = <int>[];
    for (var i = _from - 1; i >= start; i--) {
      final item = items[i];
      final text = itemText(item);
      String record;
      if (text != null) {
        final (json, end) = encodeTextRecord(item, i);
        record = end < text.length
            ? '${json.substring(0, json.length - 1)},"clip":${text.length}}'
            : json;
        _textSent[i] = end;
      } else {
        record = encodeItemRecord(item, i);
      }
      records.add((record, utf8Length(record)));
      revs.add(item.rev);
    }
    final out = <AiOutgoing>[];
    var k = 0;
    while (k < records.length) {
      final batch = <String>[];
      var size = 64;
      while (k < records.length &&
          (batch.isEmpty || size + records[k].$2 + 1 <= kAiBodyBytes)) {
        batch.add(records[k].$1);
        size += records[k].$2 + 1;
        k++;
      }
      final lowest = _from - k;
      out.add(
        _out(
          '{"v":$kAiWireVersion,"older":true,"more":${lowest > 0},'
          '"items":[${batch.reversed.join(',')}]}',
        ),
      );
    }
    _revs.insertAll(0, revs.reversed);
    _from = start;
    return out;
  }

  /// Every message up to [seq] arrived.
  void ack(int seq) => _inflight.removeWhere((e) => e.$1 <= seq);

  List<AiOutgoing> _produce({Map<String, Object?>? snapshot}) {
    _version = state.version;
    _rest = false;
    final items = state.timeline.items;
    final n = items.length;
    final budget = max(kAiBodyBytes, windowBytes - unackedBytes);
    final records = <(String, int)>[];
    var produced = 0;
    for (var i = _from; i < n; i++) {
      final k = i - _from;
      final item = items[i];
      if (k < _revs.length && _revs[k] == item.rev) continue;
      if (produced >= budget) {
        _rest = true;
        break;
      }
      final text = itemText(item);
      String record;
      if (text != null) {
        var at = _textSent[i] ?? 0;
        if (at > text.length) at = 0; // never shorter: resend it whole
        final (json, end) = encodeTextRecord(item, i, from: at);
        record = json;
        _textSent[i] = end;
        _setRev(k, end >= text.length ? item.rev : -1);
        if (end < text.length) _rest = true;
      } else {
        record = encodeItemRecord(item, i);
        _setRev(k, item.rev);
      }
      final size = utf8Length(record);
      records.add((record, size));
      produced += size + 1;
    }
    final head = jsonEncode(encodeHead(state, _indexOf));
    final headChanged = head != _head;
    _head = head;
    if (snapshot == null && records.isEmpty && !headChanged) return const [];
    final out = <AiOutgoing>[];
    var k = 0;
    var first = true;
    do {
      final prefix = StringBuffer('{"v":$kAiWireVersion,"n":$n');
      if (first && snapshot != null) {
        for (final e in snapshot.entries) {
          prefix.write(',"${e.key}":${jsonEncode(e.value)}');
        }
      }
      if (first && (headChanged || snapshot != null)) {
        prefix.write(',"head":$head');
      }
      final batch = <String>[];
      var size = utf8Length(prefix.toString()) + 16;
      while (k < records.length &&
          (batch.isEmpty || size + records[k].$2 + 1 <= kAiBodyBytes)) {
        batch.add(records[k].$1);
        size += records[k].$2 + 1;
        k++;
      }
      out.add(
        _out(
          '$prefix,"items":[${batch.join(',')}]}',
          snapshot: first && snapshot != null,
        ),
      );
      first = false;
    } while (k < records.length);
    return out;
  }

  void _setRev(int k, int rev) {
    if (k < _revs.length) {
      _revs[k] = rev;
    } else {
      _revs.add(rev);
    }
  }

  int _indexOf(TimelineItem item) {
    final items = state.timeline.items;
    for (var i = items.length - 1; i >= 0; i--) {
      if (identical(items[i], item)) return i;
    }
    return -1;
  }

  AiOutgoing _out(String body, {bool snapshot = false}) {
    final bytes = Uint8List.fromList(utf8.encode(body));
    final seq = ++_seq;
    _inflight.add((seq, bytes.length));
    return AiOutgoing(seq, bytes, snapshot: snapshot);
  }
}
