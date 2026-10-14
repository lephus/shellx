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
/// [kAiBodyBytes]: a record is cut to fit, and a header over
/// [kAiRecordBytes] loses what an agent sends without bound (its plan, its
/// mode, then a permission's options) until it fits. The strings the desktop
/// itself sets in the header (the agent's name, the folder) are taken as
/// they are, so whoever sends the bodies checks their size once more.
/// About [windowBytes] wait for an `ai.ack` at most, an [earlier] page
/// included (whether to answer at all while it is full is the hub's to
/// decide: [canSend]). Pure bookkeeping: the hub decides when to call it.
/// Kept across re-attaches of the same phone, so [AiOutgoing.seq] never goes
/// back. One that replaces another (a new runtime, a phone that left and came
/// back) is made with [afterSeq] = the old one's [lastSeq]: its first message
/// is the next number, and the phone's late ack of the old one clears nothing
/// of it.
final class AiSubscription with Redacted {
  AiSubscription(
    this.state, {
    required this.generation,
    int afterSeq = 0,
    this.attachItems = kAiAttachItems,
    this.pageItems = kAiPageItems,
    this.windowBytes = kAiWindowBytes,
  }) : _seq = afterSeq;

  final AiSessionState state;

  /// Tells this state apart from another one of the same session (a new
  /// runtime): an [AiHave] of another generation is not used.
  final int generation;
  final int attachItems;
  final int pageItems;
  final int windowBytes;

  int _seq;
  var _from = 0;

  /// The `seq` of the last message made; 0 when none was (and no
  /// subscription came before this one).
  int get lastSeq => _seq;

  /// The rev sent for each index from [_from] on; -1: the phone's copy is
  /// outdated or a text is still partial.
  final _revs = <int>[];

  /// Text items: how much of the text the phone has (UTF-16 units).
  final _textSent = <int, int>{};
  String? _head;
  var _version = -1;
  var _rest = false;
  final _inflight = <(int, int)>[];

  /// The request (a permission's or a question's id) the last header sent
  /// asks, and the `seq` of the first message whose header asked it.
  int? _asked;
  var _askedSeq = 0;

  /// The highest `seq` the phone acknowledged.
  var _acked = 0;

  /// The phone holds a header that asks [request]: it acknowledged a
  /// message that carried one (acks are cumulative). Until then a phone
  /// whose socket died unnoticed looks just like one that shows it (V2-2
  /// D11: who shows a request gets no push for it).
  bool shown(int request) => _asked == request && _acked >= _askedSeq;

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
  ///
  /// A phone more than twice [attachItems] items behind starts over from
  /// the last [attachItems], as a re-attach that far behind would (V2-2
  /// D5): one reset snapshot instead of everything it missed. While the
  /// agent starts, items after the ones the phone holds wait: that is when a
  /// restored session replays its history (`session/load`, D15), which then
  /// comes as its last [attachItems] however slowly it was replayed.
  List<AiOutgoing> delta() {
    if (!dirty) return const [];
    if (!_starting && _behind > 2 * attachItems) return attach(null);
    return _produce();
  }

  /// Items the phone was sent nothing of: the ones after those it holds.
  int get _behind => state.timeline.items.length - (_from + _revs.length);

  bool get _starting => state.phase == AgentPhase.starting;

  /// The page before index [before] (it must be [from]): whole items, the
  /// newest body first, each one continuing the held window downwards. A
  /// text longer than one piece comes cut, with `clip` = its full length.
  /// A page holds at most [pageItems] items and, like [delta], what the
  /// window has left (one body at least, and always one item): `more` stays
  /// true while items are left, and the phone asks again. Whether to answer
  /// at all while the window is full is the caller's to decide ([canSend]).
  List<AiOutgoing> earlier(int before) {
    if (before != _from || _from == 0) return const [];
    final items = state.timeline.items;
    final start = max(0, _from - pageItems);
    final budget = max(kAiBodyBytes, windowBytes - unackedBytes);
    final records = <(String, int)>[];
    final revs = <int>[];
    var produced = 0;
    for (var i = _from - 1; i >= start; i--) {
      if (records.isNotEmpty && produced >= budget) break; // the next page
      final item = items[i];
      String record;
      if (item is UserItem || item is StreamedTextItem) {
        final (json, end) = encodeTextRecord(item, i, clip: true);
        record = json;
        _textSent[i] = end;
      } else {
        record = encodeItemRecord(item, i);
      }
      final size = utf8Length(record);
      records.add((record, size));
      produced += size + 1;
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
    _from -= records.length;
    return out;
  }

  /// Every message up to [seq] arrived.
  void ack(int seq) {
    _inflight.removeWhere((e) => e.$1 <= seq);
    if (seq > _acked) _acked = seq;
  }

  List<AiOutgoing> _produce({Map<String, Object?>? snapshot}) {
    _version = state.version;
    _rest = false;
    final items = state.timeline.items;
    final n = items.length;
    final budget = max(kAiBodyBytes, windowBytes - unackedBytes);
    // New items wait while the agent starts (see [delta]); a snapshot
    // brings what there is.
    final end = snapshot == null && _starting
        ? min(n, _from + _revs.length)
        : n;
    final records = <(String, int)>[];
    var produced = 0;
    for (var i = _from; i < end; i++) {
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
    final head = _headJson();
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
      final withHead = first && (headChanged || snapshot != null);
      if (withHead) prefix.write(',"head":$head');
      final batch = <String>[];
      var size = utf8Length(prefix.toString()) + 16;
      // The first record is taken whatever its size, as only the envelope is
      // around it. With the header that is not so: the header may be bigger
      // than the 1 KiB [kAiRecordBytes] leaves, so a record that does not fit
      // beside it starts the next body (a body over [kAiBodyBytes] would drop
      // the whole channel).
      while (k < records.length &&
          ((batch.isEmpty && !withHead) ||
              size + records[k].$2 + 1 <= kAiBodyBytes)) {
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
    if (headChanged || snapshot != null) _noteAsked(out.first.seq);
    return out;
  }

  /// The header that went with message [seq] asks the request waiting now.
  void _noteAsked(int seq) {
    final request = state.currentPermission?.id ?? state.currentAsk?.id;
    if (request == _asked) return;
    _asked = request;
    _askedSeq = seq;
  }

  /// The header as JSON, within [kAiRecordBytes] so that a body holds it with
  /// its envelope (a body over [kAiBodyBytes] would drop the phone's whole
  /// channel). An agent decides how long its plan, its mode's id and a
  /// permission's options are, so when the header is too big they go, one
  /// after the other and the least needed first: the plan, the mode, then
  /// the options — the request itself (id, title) stays, so the phone knows
  /// one waits and the user answers it on the computer.
  String _headJson() {
    final head = encodeHead(state, _indexOf);
    var json = jsonEncode(head);
    final cuts = <void Function()>[
      () => head.remove('plan'),
      () => head.remove('mode'),
      () {
        if (head['perm'] case final Map<String, Object?> perm) {
          perm['options'] = const <Object?>[];
        }
      },
    ];
    for (final cut in cuts) {
      if (utf8Length(json) <= kAiRecordBytes) break;
      cut();
      json = jsonEncode(head);
    }
    return json;
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
