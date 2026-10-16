import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/design_system.dart';

class AppRefresh extends StatelessWidget {
  const AppRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.controller,
  });

  final Widget child;
  final RefreshCallback onRefresh;
  final EasyRefreshController? controller;

  @override
  Widget build(BuildContext context) {
    return EasyRefresh(
      triggerAxis: Axis.vertical,
      controller: controller,
      header: MaterialHeader(
        backgroundColor: Colors.white,
        color: context.colors.primary,
      ),
      canLoadAfterNoMore: true,
      onRefresh: onRefresh,
      child: child,
    );
  }
}
