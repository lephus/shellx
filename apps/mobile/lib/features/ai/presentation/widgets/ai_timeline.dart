import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Within this many points of the end the user counts as "at the bottom".
const double _kBottomSlack = 48;

/// How long "Tải thêm" waits for a page before it can be asked again.
const Duration _kEarlierWait = Duration(seconds: 5);

/// The conversation (V2-2 §5.2): virtualized, anchored so neither streaming
/// below nor "Tải thêm" above moves what the user reads. It follows new
/// content only while the user is at the bottom, in the very frame it arrives
/// (also when the keyboard takes room); otherwise "Mới nhất" brings them back.
///
/// Smoothness (V2-2 §5, D8):
/// - an item's widget is made once for the item the mirror holds ("keyed by (index, rev)": the mirror
///   replaces an item when its rev changes). A rebuild of the list rebuilds nothing of an item that did
///   not change, and one that changed rebuilds alone;
/// - its element is kept across revs, so an open card or an unfolded thought stays as the user left it;
/// - nothing here copies or walks the list: a thousand items cost what a screenful does.
class AiTimeline extends StatefulWidget {
  const AiTimeline({
    super.key,
    required this.mirror,
    required this.version,
    required this.agentName,
    required this.onLoadEarlier,
    this.jumpTo,
    this.clock,
  });

  final AiMirror mirror;

  /// Changes whenever [mirror] did (the controller's counter).
  final int version;
  final String agentName;

  /// "Tải thêm"; null while it cannot be asked (the link is not live).
  final VoidCallback? onLoadEarlier;

  /// An item to bring into view (the permission's tool card). It asks when it is set to an index; to
  /// ask for the same one again, set it to null in between.
  final ValueNotifier<int?>? jumpTo;

  /// The page's clock, for the tool calls that are running.
  final ReadonlySignal<DateTime>? clock;

  @override
  State<AiTimeline> createState() => _AiTimelineState();
}

/// An item's widget and what it was made for.
class _Tile {
  const _Tile(this.agent, this.clock, this.widget);
  final String agent;
  final ReadonlySignal<DateTime>? clock;
  final Widget widget;
}

class _AiTimelineState extends State<AiTimeline> {
  final _scroll = _PinnedScrollController();
  final _center = UniqueKey();

  /// The widget of each item, for as long as the mirror holds that very item (it replaces an item
  /// that changed, never changes one).
  final _tiles = Expando<_Tile>();

  /// The item a "Xem chi tiết" asked for carries this key, to be scrolled into view.
  final _revealKey = GlobalKey();
  int? _revealIndex;

  /// Items from this index on grow downwards; earlier pages grow upwards
  /// above it, so neither moves what is on screen. The first item of the
  /// first snapshot, and again at every new generation of the session.
  int? _anchor;
  int _generation = -2;
  var _atBottom = true;

  /// "Tải thêm" was asked and the page has not come ([_fromAtLoad] is where the mirror started).
  var _loadingEarlier = false;
  var _fromAtLoad = 0;
  Timer? _earlierTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncBottom);
    widget.jumpTo?.addListener(_onJump);
  }

  @override
  void didUpdateWidget(AiTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jumpTo != widget.jumpTo) {
      oldWidget.jumpTo?.removeListener(_onJump);
      widget.jumpTo?.addListener(_onJump);
    }
    final mirror = widget.mirror;
    if (_loadingEarlier && (mirror.from != _fromAtLoad || !mirror.hasEarlier)) _endLoadingEarlier();
    if (oldWidget.version != widget.version) {
      // What arrived may have changed how far the end is (content that grew while the user was
      // scrolling, say): look again once it is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncBottom());
    }
  }

  @override
  void dispose() {
    widget.jumpTo?.removeListener(_onJump);
    _earlierTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _syncBottom() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final atBottom = position.extentAfter < _kBottomSlack;
    if (atBottom == _atBottom) return;
    // A scroll position can move while the page is laid out: show the button after it.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncBottom());
      return;
    }
    setState(() => _atBottom = atBottom);
  }

  void _loadEarlier() {
    if (_loadingEarlier || widget.onLoadEarlier == null) return;
    // One request per page: a second one before the first is answered would ask the computer for the
    // same page again, which the mirror could not take.
    setState(() {
      _loadingEarlier = true;
      _fromAtLoad = widget.mirror.from;
    });
    _earlierTimer?.cancel();
    _earlierTimer = Timer(_kEarlierWait, () {
      if (mounted) setState(() => _loadingEarlier = false);
    });
    widget.onLoadEarlier!();
  }

  void _endLoadingEarlier() {
    _earlierTimer?.cancel();
    _earlierTimer = null;
    _loadingEarlier = false;
  }

  void _latest() {
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll
          .animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          )
          .then((_) {
            // The end of a list of unequal items is only known once it is reached.
            if (mounted && _scroll.hasClients && _scroll.position.extentAfter > 1) {
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          }),
    );
  }

  void _onJump() {
    final index = widget.jumpTo?.value;
    if (index == null || widget.mirror.at(index) == null) return;
    setState(() => _revealIndex = index);
    _reveal(index, 3);
  }

  /// Brings the item into view. It is built only near the screen: when it is not, the end of the
  /// conversation (where a waiting request's card is) is brought in and the item looked for again.
  void _reveal(int index, int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _revealIndex != index || !_scroll.hasClients) return;
      final target = _revealKey.currentContext;
      if (target != null) {
        unawaited(Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 150), alignment: 0.2));
        return;
      }
      if (tries == 0) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      _reveal(index, tries - 1);
    });
  }

  Widget _tile(MirrorItem item) {
    final agent = widget.agentName;
    final clock = widget.clock;
    final cached = _tiles[item];
    if (cached != null && cached.agent == agent && identical(cached.clock, clock)) return cached.widget;
    final made = Padding(
      key: ValueKey(item.index),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: AiItemView(item: item, agentName: agent, clock: clock),
    );
    _tiles[item] = _Tile(agent, clock, made);
    return made;
  }

  Widget? _build(int index) {
    final item = widget.mirror.at(index);
    if (item == null) return null;
    final tile = _tile(item);
    return index == _revealIndex ? KeyedSubtree(key: _revealKey, child: tile) : tile;
  }

  @override
  Widget build(BuildContext context) {
    final mirror = widget.mirror;
    final from = mirror.from;
    final end = mirror.end;
    if (end <= from) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            S.of(context).aiEmpty,
            textAlign: TextAlign.center,
            style: context.typo.paragraph.copyWith(color: context.colors.secondaryText),
          ),
        ),
      );
    }
    if (_anchor == null || mirror.generation != _generation || _anchor! >= end) {
      // The first look, or another session behind the same page: start at the latest.
      _anchor = from;
      _generation = mirror.generation;
      _scroll.stickOnce();
    }
    final anchor = _anchor! < from ? from : _anchor!;
    return Stack(
      children: [
        // One selection area for the whole conversation: the text of a message, a paragraph, a list item
        // is selected and copied by a long press, with no editor of its own to build for each (V2-2 fix
        // round 1). The items keep their keep-alive wrappers, which hold an item that has a selection
        // when it scrolls out of the screen, so the selection is not lost. The button below is outside.
        SelectionArea(
          child: CustomScrollView(
            key: const Key('ai.timeline'),
            controller: _scroll,
            center: _center,
            // Slivers before [center] stack upwards from it: the page of older
            // items right above the newer ones, "Tải thêm" at the very top.
            slivers: [
              if (mirror.hasEarlier)
                SliverToBoxAdapter(
                  child: Center(
                    child: TextButton(
                      key: const Key('ai.loadEarlier'),
                      onPressed: _loadingEarlier || widget.onLoadEarlier == null ? null : _loadEarlier,
                      child: Text(S.of(context).aiLoadEarlier),
                    ),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, position) => _build(anchor - 1 - position),
                  childCount: anchor - from,
                ),
              ),
              SliverList(
                key: _center,
                delegate: SliverChildBuilderDelegate(
                  (_, position) => _build(anchor + position),
                  childCount: end - anchor,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        ),
        if (!_atBottom)
          Positioned(
            right: 12,
            bottom: 8,
            child: FloatingActionButton.small(
              key: const Key('ai.latest'),
              heroTag: null,
              tooltip: S.of(context).aiJumpLatest,
              onPressed: _latest,
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
    );
  }
}

/// A scroll controller whose position keeps the end of the content in view while it is there: new
/// items below, a text that grows, a keyboard that takes room. The position does it while the list is
/// laid out, so the new content is on screen in the same frame, with no second layout and no jump.
class _PinnedScrollController extends ScrollController {
  _PinnedScrollController() : super(keepScrollOffset: false);

  /// [stickOnce] before there is a position: the first one takes it.
  bool _stickNext = false;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) =>
      _PinnedPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (_stickNext && position is _PinnedPosition) {
      position.stickOnce();
      _stickNext = false;
    }
  }

  /// The next layout puts the end in view, wherever the user was.
  void stickOnce() {
    if (!hasClients) {
      _stickNext = true;
      return;
    }
    for (final position in positions) {
      if (position is _PinnedPosition) position.stickOnce();
    }
  }
}

class _PinnedPosition extends ScrollPositionWithSingleContext {
  _PinnedPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  var _force = false;
  var _corrections = 0;

  void stickOnce() => _force = true;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // At the end before this layout (the first one counts), and not in the user's hands.
    final atEnd = !hasContentDimensions || pixels >= this.maxScrollExtent - _kBottomSlack;
    final follow = (_force || atEnd) && userScrollDirection == ScrollDirection.idle;
    // The extent of a list of unequal items is an estimate until its end is laid out: more than one
    // pass may be needed, a few at most.
    if (follow && (maxScrollExtent - pixels).abs() > 0.5 && _corrections < 4) {
      _corrections++;
      correctPixels(maxScrollExtent);
      super.applyContentDimensions(minScrollExtent, maxScrollExtent);
      return false;
    }
    _corrections = 0;
    _force = false;
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
