import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final regular = Uint8List.fromList(List.filled(16, 1));
  final italic = Uint8List.fromList(List.filled(16, 2));

  late List<MethodCall> calls;
  late List<(String, List<Uint8List>)> registered;
  late List<String> logs;

  void answer(Future<Object?> Function() reply) {
    messenger.setMockMethodCallHandler(ShellxSystemFont.channel, (call) {
      calls.add(call);
      return reply();
    });
  }

  Future<void> register(String family, List<Uint8List> fonts) async {
    registered.add((family, fonts));
  }

  Future<ShellxFontStatus> load({
    TargetPlatform platform = TargetPlatform.macOS,
    bool enabled = true,
    ShellxFontRegistrar? registrar,
  }) => ShellxSystemFont.loadWith(
    platform: platform,
    enabled: enabled,
    register: registrar ?? register,
    log: logs.add,
  );

  setUp(() {
    calls = [];
    registered = [];
    logs = [];
  });

  tearDown(
    () => messenger.setMockMethodCallHandler(ShellxSystemFont.channel, null),
  );

  test(
    'bytes: the loader gets "SF Mono" with the upright and the italic',
    () async {
      answer(
        () async => {'regular': regular, 'italic': italic, 'missing': <int>[]},
      );
      final status = await load();
      expect(status, const ShellxFontStatus.loaded());
      expect(status.isLoaded, isTrue);
      expect(calls.single.method, 'monospaced');
      expect(calls.single.arguments, isNull);
      expect(registered.single.$1, 'SF Mono');
      expect(registered.single.$2, [regular, italic]);
      expect(logs, isEmpty);
    },
  );

  test('no italic: the upright alone', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    expect(await load(), const ShellxFontStatus.loaded());
    expect(registered.single.$2, [regular]);
  });

  test('iOS asks the runner too', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    expect(
      await load(platform: TargetPlatform.iOS),
      const ShellxFontStatus.loaded(),
    );
    expect(calls, hasLength(1));
  });

  group('every failure registers nothing and falls back, without throwing', () {
    final cases =
        <String, (Future<Object?> Function(), ShellxFontFallbackReason)>{
          'an error': (
            () async => throw PlatformException(code: 'unavailable'),
            ShellxFontFallbackReason.channel,
          ),
          'null': (() async => null, ShellxFontFallbackReason.channel),
          'not a map': (() async => 'x', ShellxFontFallbackReason.channel),
          'no upright': (
            () async => {'italic': italic, 'missing': <int>[]},
            ShellxFontFallbackReason.channel,
          ),
          'empty upright': (
            () async => {'regular': Uint8List(0), 'missing': <int>[]},
            ShellxFontFallbackReason.channel,
          ),
          'no missing list': (
            () async => {'regular': regular},
            ShellxFontFallbackReason.channel,
          ),
          'a missing letter': (
            () async => {
              'regular': regular,
              'italic': italic,
              'missing': [0x1EA0],
            },
            ShellxFontFallbackReason.coverage,
          ),
          'over 500 ms': (
            () => Future<Object?>.delayed(
              const Duration(milliseconds: 700),
              () => {'regular': regular, 'missing': <int>[]},
            ),
            ShellxFontFallbackReason.timeout,
          ),
        };
    cases.forEach((name, c) {
      test(name, () async {
        answer(c.$1);
        final status = await load();
        expect(status, ShellxFontStatus.fallback(c.$2));
        expect(status.isLoaded, isFalse);
        expect(registered, isEmpty);
        expect(logs, ['ShellX: SF Mono not loaded (${c.$2.name})']);
      });
    });

    test('no runner (MissingPluginException)', () async {
      final status = await load();
      expect(
        status,
        const ShellxFontStatus.fallback(ShellxFontFallbackReason.channel),
      );
      expect(registered, isEmpty);
    });

    test('the engine refuses the bytes', () async {
      answer(() async => {'regular': regular, 'missing': <int>[]});
      final status = await load(
        registrar: (_, _) async => throw Exception('bad font'),
      );
      expect(
        status,
        const ShellxFontStatus.fallback(ShellxFontFallbackReason.loader),
      );
      expect(logs, ['ShellX: SF Mono not loaded (loader)']);
    });
  });

  test('Android, Windows, Linux: the runner is never asked', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        await load(platform: platform),
        const ShellxFontStatus.fallback(ShellxFontFallbackReason.unsupported),
      );
    }
    expect(calls, isEmpty);
    expect(registered, isEmpty);
    expect(logs, isEmpty);
  });

  test('switched off: the runner is never asked', () async {
    answer(() async => {'regular': regular, 'missing': <int>[]});
    expect(
      await load(enabled: false),
      const ShellxFontStatus.fallback(ShellxFontFallbackReason.unsupported),
    );
    expect(calls, isEmpty);
  });

  test('the switches default to on (A32)', () {
    expect(ShellxSystemFont.enabled, isTrue);
    expect(ShellxSystemFont.enabledOnMacOS, isTrue);
    expect(ShellxSystemFont.enabledOnIOS, isTrue);
    expect(ShellxSystemFont.timeout, const Duration(milliseconds: 500));
    expect(ShellxSystemFont.channel.name, 'pro.shellx.design/system_font');
  });

  test('toString carries no content', () {
    expect(const ShellxFontStatus.loaded().toString(), 'ShellxFontStatus(…)');
    expect(
      const ShellxFontStatus.fallback(
        ShellxFontFallbackReason.coverage,
      ).toString(),
      'ShellxFontStatus(…)',
    );
  });
}
