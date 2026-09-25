import 'package:flutter/foundation.dart';
import 'package:toastification/toastification.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/src/assets.gen.dart';

@lazySingleton
class PopupHandler {
  final BuildContext rootContext;

  PopupHandler(this.rootContext);

  BuildContext? envContext;

  Future<T?> show<T>(
    Widget content, {
    bool barrierDismissible = true,
  }) async {
    if (envContext != null && envContext?.mounted == true) {
      hide();
    }
    return showDialog<T>(
      context: rootContext,
      useRootNavigator: true,
      barrierDismissible: barrierDismissible,
      builder: (context) {
        envContext = context;
        return content;
      },
    );
  }

  Future<void> showLoading({String? title}) async {
    await show(
      Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: LoadingWidget(
            title: title ?? 'Loading...',
          ),
        ),
      ),
    );
  }

  void hide() {
    try {
      if (envContext != null) {
        Navigator.of(envContext!).pop();
        envContext = null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PopupHandler hide error: ${e.runtimeType}');
    }
  }

  void showMessage({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    Widget? icon,
  }) {
    hide();
    toastification.dismissAll(delayForAnimation: false);
    final color = switch (type) {
      (ToastificationType.error) => rootContext.colors.mainRed,
      (ToastificationType.success) => rootContext.colors.mainGreen,
      (ToastificationType.warning) => Colors.yellowAccent,
      _ => Colors.blueAccent,
    };
    toastification.show(
      context: rootContext,
      type: type,
      style: ToastificationStyle.flat,
      autoCloseDuration: const Duration(seconds: 3),
      title: Text(title),

      description: description != null
          ? RichText(
              text: TextSpan(
                text: description,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 14,
                ),
              ),
            )
          : null,
      alignment: Alignment.topCenter,
      direction: TextDirection.ltr,
      animationDuration: const Duration(milliseconds: 300),
      animationBuilder: (context, animation, alignment, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      icon: icon,
      showIcon: true, // show or hide the icon
      primaryColor: color,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      dismissDirection: DismissDirection.up,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07000000),
          blurRadius: 16,
          offset: Offset(0, 16),
          spreadRadius: 0,
        ),
      ],
      showProgressBar: false,
      closeOnClick: false,
      pauseOnHover: true,
      dragToClose: true,

      callbacks: callbacks,
    );
  }

  void showSuccess({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) {
    showMessage(
      title: title,
      description: description,
      icon: Assets.icons.icTick.svg(width: 24, height: 24),
      type: ToastificationType.success,
    );
  }

  void showError({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) {
    showMessage(
      title: title,
      description: description,
      icon: Assets.icons.icClose.svg(width: 24, height: 24),
      type: ToastificationType.error,
    );
  }

  void showInfo({
    ToastificationCallbacks callbacks = const ToastificationCallbacks(),
    ToastificationType? type,
    required String title,
    String? description,
    IconData? icon,
  }) {
    showMessage(
      title: title,
      description: description,
      icon: const Icon(
        Icons.info,
        color: Colors.blueAccent,
      ),
      type: ToastificationType.info,
    );
  }
}

class LoadingWidget extends StatelessWidget {
  final String title;
  const LoadingWidget({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 30,
            child: Center(
              child: CircularProgressIndicator(
                color: context.colors.primaryText,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(title),
        ],
      ),
    );
  }
}
