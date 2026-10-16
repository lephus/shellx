import 'package:flutter/cupertino.dart';
import 'package:shellx_mobile/core/core.dart';

extension PushTransparentRoute on BuildContext {
  void pushTransparentRoute(Widget widget) {
    Navigator.of(this).push(
      AppTransparentRoute(builder: (context) => widget),
    );
  }
}

class AppTransparentRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  AppTransparentRoute({
    required this.builder,
    this.backgroundColor = Colors.black12,
    this.transitionDuration = const Duration(milliseconds: 250),
    this.reverseTransitionDuration = const Duration(milliseconds: 500),
    super.barrierDismissible = false,
    this.title,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog = true,
  });

  final WidgetBuilder builder;

  @override
  final String? title;

  /// Builds the primary contents of the route.
  @override
  final bool maintainState;

  @override
  final Duration transitionDuration;

  @override
  final Duration reverseTransitionDuration;

  final Color backgroundColor;

  @override
  Color get barrierColor => backgroundColor;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';

  @override
  bool get opaque => false;
}
