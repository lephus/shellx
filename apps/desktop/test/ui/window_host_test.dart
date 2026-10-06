import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/ui/window_bounds.dart';
import 'package:shellx_desktop/src/ui/window_host.dart';

/// Records every native call; [minimized], [maximized] and [fullScreen]
/// script the window's state.
final class _FakeNative implements NativeWindow {
  final calls = <String>[];
  bool minimized = false;
  bool maximized = false;
  bool fullScreen = false;
  Rect bounds = const Rect.fromLTWH(10, 20, 1000, 700);

  Future<void> _record(String call) async => calls.add(call);

  @override
  Future<bool> isMinimized() async => minimized;
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Future<bool> isFullScreen() async => fullScreen;
  @override
  Future<void> restore() async {
    calls.add('restore');
    minimized = false;
  }

  @override
  Future<void> maximize() => _record('maximize');
  @override
  Future<void> show() => _record('show');
  @override
  Future<void> hide() => _record('hide');
  @override
  Future<void> focus() => _record('focus');
  @override
  Future<Rect> getBounds() async => bounds;
  @override
  Future<void> setBounds(Rect bounds) => _record('setBounds $bounds');
  @override
  Future<void> setSize(Size size) => _record('setSize $size');
  @override
  Future<void> center() => _record('center');
  @override
  Future<void> activateApp() => _record('activate');
  @override
  Future<void> setDockVisible(bool visible) => _record('dock $visible');
  @override
  Future<void> setSkipTaskbar(bool skip) => _record('skipTaskbar $skip');
}

void main() {
  late _FakeNative native;
  late InMemorySettingsStore settings;

  WindowManagerHost host({bool macos = true}) => WindowManagerHost(
    onCloseRequested: () {},
    bounds: WindowBoundsStore(settings),
    displays: () async => const [Rect.fromLTWH(0, 0, 1440, 900)],
    native: native,
    macos: macos,
    windows: !macos,
  );

  setUp(() {
    native = _FakeNative();
    settings = InMemorySettingsStore();
  });

  test('window_manager focus and blur reach onFocusChanged (A4 D25)', () {
    final focus = <bool>[];
    final h = WindowManagerHost(
      onCloseRequested: () {},
      bounds: WindowBoundsStore(settings),
      native: native,
      onFocusChanged: focus.add,
    );
    h.onWindowFocus();
    h.onWindowBlur();
    expect(focus, [true, false]);
  });

  test('minimizing counts as losing the focus (A4 D25 backstop)', () {
    final focus = <bool>[];
    final h = WindowManagerHost(
      onCloseRequested: () {},
      bounds: WindowBoundsStore(settings),
      native: native,
      onFocusChanged: focus.add,
    );
    h.onWindowFocus();
    h.onWindowMinimize();
    expect(focus, [true, false]);
  });

  group('bringToFront (ruling C1)', () {
    test('a minimized window is restored, shown, focused and the app '
        'activated (macOS)', () async {
      native.minimized = true;
      await host().bringToFront();
      expect(native.calls, ['restore', 'show', 'focus', 'activate']);
    });

    test('a window behind another app is shown and focused; nothing to '
        'restore', () async {
      await host().bringToFront();
      expect(native.calls, ['show', 'focus', 'activate']);
    });

    test('Windows: no app activation call (focus brings it forward)', () async {
      native.minimized = true;
      await host(macos: false).bringToFront();
      expect(native.calls, ['restore', 'show', 'focus']);
    });

    test(
      'show() places the window once, then brings it to the front',
      () async {
        final h = host();
        await h.show();
        expect(native.calls, [
          'setSize ${const Size(1100, 720)}',
          'center',
          'dock true',
          'show',
          'focus',
          'activate',
        ]);
        native.calls.clear();
        native.minimized = true;
        await h.show();
        expect(native.calls, [
          'dock true',
          'restore',
          'show',
          'focus',
          'activate',
        ]);
      },
    );
  });

  group('remembered bounds (final-wave minor)', () {
    test('a normal window saves its bounds and not-maximized', () async {
      await host().saveBounds();
      final store = WindowBoundsStore(settings);
      expect(store.read(), const Rect.fromLTWH(10, 20, 1000, 700));
      expect(store.readMaximized(), isFalse);
    });

    test('maximized: the last normal bounds are kept, maximized is '
        'remembered', () async {
      final store = WindowBoundsStore(settings);
      await store.write(const Rect.fromLTWH(40, 60, 1100, 720));
      native
        ..maximized = true
        ..bounds = const Rect.fromLTWH(0, 0, 1440, 900);
      await host().saveBounds();
      expect(store.read(), const Rect.fromLTWH(40, 60, 1100, 720));
      expect(store.readMaximized(), isTrue);
    });

    test('full screen counts as maximized', () async {
      native.fullScreen = true;
      await host().saveBounds();
      final store = WindowBoundsStore(settings);
      expect(store.read(), isNull);
      expect(store.readMaximized(), isTrue);
    });

    test('a remembered maximized window opens over its normal bounds, then '
        'maximizes', () async {
      final store = WindowBoundsStore(settings);
      await store.write(const Rect.fromLTWH(40, 60, 1100, 720));
      await store.writeMaximized(true);
      await host().show();
      expect(
        native.calls.first,
        'setBounds ${const Rect.fromLTWH(40, 60, 1100, 720)}',
      );
      expect(native.calls.last, 'maximize');
    });

    test('the maximized key is in the shared_preferences allow-list', () {
      expect(SettingKeys.all, contains(SettingKeys.windowMaximized));
    });
  });
}
