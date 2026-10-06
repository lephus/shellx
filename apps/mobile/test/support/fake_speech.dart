import 'dart:async';

import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

/// Synchronous events; every call is recorded.
class FakeSpeechInput implements SpeechInput {
  final StreamController<SpeechEvent> _events = StreamController<SpeechEvent>.broadcast(sync: true);

  SpeechPermission permission = SpeechPermission.granted;

  @override
  bool tryOnDeviceFirst = true;

  /// Completes [ensurePermission] when set (to hold it open in a test).
  Completer<void>? permissionGate;

  Map<VoiceLocale, String?> localeIds = {VoiceLocale.vi: 'vi-VN', VoiceLocale.en: 'en-US'};

  final List<({String localeId, bool onDevice})> starts = [];
  int permissionCalls = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  void emit(SpeechEvent event) => _events.add(event);

  @override
  Future<SpeechPermission> ensurePermission() async {
    permissionCalls++;
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<String?> resolveLocale(VoiceLocale locale) async => localeIds[locale];

  @override
  Future<void> start(String localeId, {required bool onDevice}) async {
    starts.add((localeId: localeId, onDevice: onDevice));
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;
}
