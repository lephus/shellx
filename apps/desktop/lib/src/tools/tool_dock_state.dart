/// V2-3 D3, D5, D14: one workspace's tool dock — open or not, zoomed or
/// not, its width, the tool on show and the chips — and where it goes in
/// the window. Pure Dart: the restore file (`toolDock`) holds it as is.
library;

import 'dart:math' as math;

import 'tool_entry.dart' show kMaxToolsPerWorkspace, kToolIdPattern;

/// D3: 45 % of the content area by default.
const double kToolDockDefaultWidth = 0.45;

/// D3: the dock is at least 320 px; the panes keep at least 360 px.
const double kToolDockMinWidth = 320;
const double kToolPaneMinWidth = 360;

/// The strip between the panes and the dock that drags its width.
const double kToolDockHandle = 6;

/// A stored width outside this range is repaired.
const double _minFraction = 0.1, _maxFraction = 0.9;

final class ToolDockState {
  const ToolDockState({
    this.open = false,
    this.zoom = false,
    this.width = kToolDockDefaultWidth,
    this.active,
    this.tools = const [],
  });

  final bool open;

  /// D3 "Expand": the dock covers the whole content area.
  final bool zoom;

  /// A fraction of the content area.
  final double width;

  /// The tool on show (one of [tools]).
  final String? active;

  /// D5: the open tools, one chip each, in the order they were opened.
  final List<String> tools;

  /// Nothing worth keeping in `layout.json`.
  bool get isDefault =>
      !open && !zoom && width == kToolDockDefaultWidth && tools.isEmpty;

  ToolDockState copyWith({
    bool? open,
    bool? zoom,
    double? width,
    String? active,
    List<String>? tools,
  }) => ToolDockState(
    open: open ?? this.open,
    zoom: zoom ?? this.zoom,
    width: width ?? this.width,
    active: active ?? this.active,
    tools: tools ?? this.tools,
  );

  /// D5: [toolId] (already a chip) on show.
  ToolDockState activated(String toolId) =>
      tools.contains(toolId) ? copyWith(active: toolId) : this;

  /// D4: open, with [toolId] on show (a chip of its own at the end).
  ToolDockState opened(String toolId) => ToolDockState(
    open: true,
    zoom: zoom,
    width: width,
    active: toolId,
    tools: tools.contains(toolId) ? tools : [...tools, toolId],
  );

  /// D5, D10: [toolId]'s chip closes; the one after it (else before it)
  /// shows; with none left the dock closes and leaves its zoom.
  ToolDockState without(String toolId) {
    final at = tools.indexOf(toolId);
    if (at < 0) return this;
    final rest = [...tools]..removeAt(at);
    if (rest.isEmpty) {
      return ToolDockState(width: width);
    }
    final next = active == toolId
        ? rest[math.min(at, rest.length - 1)]
        : active;
    return ToolDockState(
      open: open,
      zoom: zoom,
      width: width,
      active: next,
      tools: rest,
    );
  }

  Map<String, Object?> toJson() => {
    'open': open,
    'zoom': zoom,
    'width': width,
    'active': active,
    'tools': tools,
  };

  /// D14, lenient: null only for something that is not an object; a
  /// damaged field is repaired (a bad width is the default, unknown ids go,
  /// an open dock without chips is closed).
  static ToolDockState? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final rawTools = raw['tools'];
    final tools = <String>[];
    if (rawTools is List) {
      for (final t in rawTools) {
        if (t is String &&
            kToolIdPattern.hasMatch(t) &&
            !tools.contains(t) &&
            tools.length < kMaxToolsPerWorkspace) {
          tools.add(t);
        }
      }
    }
    final width = raw['width'];
    final active = raw['active'];
    return ToolDockState(
      open: raw['open'] == true && tools.isNotEmpty,
      zoom: raw['zoom'] == true && tools.isNotEmpty,
      width: width is num && width >= _minFraction && width <= _maxFraction
          ? width.toDouble()
          : kToolDockDefaultWidth,
      active: active is String && tools.contains(active)
          ? active
          : tools.firstOrNull,
      tools: List.unmodifiable(tools),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ToolDockState &&
      other.open == open &&
      other.zoom == zoom &&
      other.width == width &&
      other.active == active &&
      _sameList(other.tools, tools);

  @override
  int get hashCode =>
      Object.hash(open, zoom, width, active, Object.hashAll(tools));

  @override
  String toString() =>
      'ToolDockState(open: $open, zoom: $zoom, tools: ${tools.length})';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Where the panes and the dock go in a content area (D3, §8).
final class ToolDockLayout {
  const ToolDockLayout({
    required this.paneWidth,
    required this.dockLeft,
    required this.dockWidth,
  });

  /// The panes' width. Kept while the dock is zoomed over them, so no
  /// terminal is resized by a zoom.
  final double paneWidth;

  /// Null: no dock on screen.
  final double? dockLeft;
  final double dockWidth;

  bool get showsDock => dockLeft != null;

  /// The drag strip sits between the panes and a dock that is not zoomed.
  bool get showsHandle => dockLeft != null && dockLeft! > 0;
}

/// D3, §8: the dock of [dock] in a content area [width] wide. A dock that
/// does not fit beside 360 px of panes is shown only zoomed.
ToolDockLayout toolDockLayout({
  required double width,
  required ToolDockState? dock,
  required bool embedded,
}) {
  final show = embedded && dock != null && dock.open && dock.tools.isNotEmpty;
  if (!show) {
    return ToolDockLayout(paneWidth: width, dockLeft: null, dockWidth: 0);
  }
  final room = width - kToolDockHandle;
  final fits = room >= kToolPaneMinWidth + kToolDockMinWidth;
  final dockWidth = fits
      ? (width * dock.width)
            .clamp(kToolDockMinWidth, room - kToolPaneMinWidth)
            .roundToDouble()
      : 0.0;
  final paneWidth = fits ? room - dockWidth : width;
  if (dock.zoom) {
    return ToolDockLayout(paneWidth: paneWidth, dockLeft: 0, dockWidth: width);
  }
  if (!fits) {
    return ToolDockLayout(paneWidth: width, dockLeft: null, dockWidth: 0);
  }
  return ToolDockLayout(
    paneWidth: paneWidth,
    dockLeft: paneWidth + kToolDockHandle,
    dockWidth: dockWidth,
  );
}

/// The width fraction a drag to [dockWidth] pixels keeps (clamped to the
/// pixel minimums of [toolDockLayout]).
double toolDockFraction({required double width, required double dockWidth}) {
  final room = width - kToolDockHandle;
  if (room < kToolPaneMinWidth + kToolDockMinWidth) {
    return kToolDockDefaultWidth;
  }
  final px = dockWidth.clamp(kToolDockMinWidth, room - kToolPaneMinWidth);
  return (px / width).clamp(_minFraction, _maxFraction).toDouble();
}
