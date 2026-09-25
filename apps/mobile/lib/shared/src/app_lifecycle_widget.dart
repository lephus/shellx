import 'package:flutter/material.dart';

class AppLifecycleWidget extends StatefulWidget {
  const AppLifecycleWidget({super.key});

  @override
  State<AppLifecycleWidget> createState() => AppLifecycleWidgetState();
}

class AppLifecycleWidgetState<T extends AppLifecycleWidget> extends State<T> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime flagLastVisible = DateTime.now();
  bool appIsPaused = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (enableLifeCircleLog) print('DEBUG: App lifecycle state changed to $state');
    if (state == AppLifecycleState.paused) {
      flagLastVisible = DateTime.now();
      appIsPaused = true;
    }

    if (state == AppLifecycleState.resumed && appIsPaused) {
      appIsPaused = false;
      final now = DateTime.now();
      final duration = now.difference(flagLastVisible);
      if (duration > Duration(minutes: 1)) {
        onResume();
        if (enableLifeCircleLog) print('DEBUG: App resumed, reloading configs');
      } else {
        if (enableLifeCircleLog) print('DEBUG: App resumed, background < 1m -> dont reload config');
      }
    }
  }

  void onResume() {}

  bool get enableLifeCircleLog => false;

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError();
  }
}
