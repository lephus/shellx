import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/design_system.dart';
import 'sliver_bottom_padding.dart';

abstract class IAppScrollView extends StatelessWidget {
  IAppScrollView({
    super.key,
    required this.slivers,
    required this.onRefresh,
    this.pageStorageKey,
    this.scrollController,
  });

  final List<Widget> slivers;
  final Future<void> Function() onRefresh;
  final PageStorageKey<dynamic>? pageStorageKey;
  final ScrollController? scrollController;

  late final List<Widget> sliversDecorated = [...slivers, sliverBottomPadding];
}

class AndroidScrollView extends IAppScrollView {
  AndroidScrollView({
    super.key,
    required super.slivers,
    required super.onRefresh,
    super.pageStorageKey,
    super.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: onRefresh,
      child: CustomScrollView(
        controller: scrollController,
        key: pageStorageKey,
        slivers: sliversDecorated,
      ),
    );
  }
}

class IOSScrollView extends IAppScrollView {
  IOSScrollView({
    super.key,
    required super.slivers,
    required super.onRefresh,
    super.pageStorageKey,
    super.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: pageStorageKey,
      controller: scrollController,
      slivers: [
        CupertinoSliverRefreshControl(
          refreshIndicatorExtent: 100,
          refreshTriggerPullDistance: 150,
          onRefresh: onRefresh,
        ),
        ...sliversDecorated,
      ],
    );
  }
}

class AppScrollView extends IAppScrollView {
  AppScrollView({
    super.key,
    required super.slivers,
    required super.onRefresh,
    super.pageStorageKey,
    super.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    return Visibility(
      visible: isIOS,
      replacement: AndroidScrollView(
        slivers: slivers,
        onRefresh: onRefresh,
        pageStorageKey: pageStorageKey,
        scrollController: scrollController,
      ),
      child: IOSScrollView(
        slivers: slivers,
        onRefresh: onRefresh,
        pageStorageKey: pageStorageKey,
        scrollController: scrollController,
      ),
    );
  }
}
