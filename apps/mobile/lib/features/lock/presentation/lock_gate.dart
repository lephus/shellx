import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/biometric_method.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Covers the whole app with [LockScreen] while [lock] is locked and feeds
/// app lifecycle changes to the lock and to [onBackground]/[onForeground].
///
/// It wraps the router's navigator (`MaterialApp.router(builder:)`), not a route: the lock must
/// also engage when the app returns from the background, which is no navigation event.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.lock,
    required this.child,
    this.onBackground,
    this.onForeground,
  });

  final AppLockController lock;
  final Widget child;

  /// Called when the app is paused (suspend the relay, spec §12).
  final VoidCallback? onBackground;

  /// Called every time the app returns to the foreground (reconnect, spec §9.4).
  final VoidCallback? onForeground;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  late final AppLifecycleListener _lifecycle;
  late final void Function() _stopUnfocus;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume);
    // Keep keystrokes (soft or hardware keyboard) away from the hidden terminal.
    _stopUnfocus = widget.lock.isLocked.subscribe((locked) {
      if (locked) FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _onPause() {
    widget.lock.onBackgrounded();
    widget.onBackground?.call();
  }

  void _onResume() {
    widget.lock.onForegrounded();
    widget.onForeground?.call();
  }

  @override
  void dispose() {
    _stopUnfocus();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final locked = widget.lock.isLocked.value;
      return Stack(
        children: [
          ExcludeFocus(excluding: locked, child: widget.child),
          // BlockSemantics drops the hidden terminal's accessibility nodes too, not only its
          // focus (a screen reader must not be able to swipe past the lock screen).
          if (locked)
            Positioned.fill(
              child: BlockSemantics(child: LockScreen(lock: widget.lock)),
            ),
        ],
      );
    });
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});

  final AppLockController lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Prompt right away; the button retries after a cancelled prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    await widget.lock.unlock(S.of(context).lockReason);
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Watch((context) {
              final kind = widget.lock.kind.value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShellxLogo(),
                  18.sizedHeight,
                  Text(strings.lockTitle, textAlign: TextAlign.center, style: context.typo.heading26.heavy),
                  12.sizedHeight,
                  Text(
                    strings.lockSubtitle,
                    textAlign: TextAlign.center,
                    style: context.typo.subHeader15.copyWith(color: context.colors.secondaryText),
                  ),
                  28.sizedHeight,
                  StatusCircle(icon: biometricIcon(kind)),
                  32.sizedHeight,
                  AppButton(
                    title: strings.lockUnlockWith(biometricMethod(strings, kind)),
                    width: double.infinity,
                    state: widget.lock.isAuthenticating.value ? ButtonState.loading : ButtonState.available,
                    onTap: _unlock,
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
