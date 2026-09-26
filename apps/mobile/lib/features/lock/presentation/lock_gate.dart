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

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;
  late final void Function() _stopUnfocus;

  /// True while the app is not in the foreground and the biometric lock is on:
  /// the iOS app switcher and Android recents snapshot the screen then, and
  /// must never show terminal output.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    // Registered before the router (this widget is the router's ancestor, so its
    // initState runs first), so this observer is asked about a system back first.
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(onPause: _onPause, onResume: _onResume, onStateChange: _onStateChange);
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

  void _onStateChange(AppLifecycleState state) {
    final covered = switch (state) {
      AppLifecycleState.resumed => false,
      AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.paused => widget.lock.isEnabled,
      AppLifecycleState.detached => _covered,
    };
    if (covered != _covered && mounted) setState(() => _covered = covered);
  }

  /// Android system back while locked: consumed, so the routes hidden under the
  /// lock screen never pop.
  @override
  Future<bool> didPopRoute() async => widget.lock.isLocked.peek();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          // The cover is visual only: excluding focus while merely `_covered` (not `locked`)
          // would drop the terminal's soft-keyboard focus every time the app switcher snapshot
          // is taken, and it never comes back.
          ExcludeFocus(excluding: locked, child: widget.child),
          // BlockSemantics drops the hidden terminal's accessibility nodes too, not only its
          // focus (a screen reader must not be able to swipe past the lock screen).
          if (locked)
            Positioned.fill(
              child: BlockSemantics(child: LockScreen(lock: widget.lock)),
            ),
          if (_covered) const Positioned.fill(child: BlockSemantics(child: PrivacyCover())),
        ],
      );
    });
  }
}

/// What the app switcher shows while the biometric lock is on: the app
/// background with the ShellX logo, never the screen underneath.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background,
      child: const Center(child: ShellxLogo()),
    );
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
