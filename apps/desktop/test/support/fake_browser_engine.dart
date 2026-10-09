import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:shellx_desktop/src/browser/browser_bridge.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';

/// Test double: records calls, lets tests push engine events.
final class FakeBrowserEngine implements BrowserEngine {
  FakeBrowserEngine({this.transport = BridgeTransport.webkit});

  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast(sync: true);
  @override
  final BridgeTransport transport;

  final List<Uri> loads = [];
  final List<String> calls = [];
  final List<String> scripts = [];
  List<String> forwarded = const [];
  Object? scriptError;

  /// When set, [runScript] waits for it (a slow engine).
  Completer<void>? scriptGate;
  Uint8List png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
  void Function()? onCapture;
  bool disposed = false;

  void emit(BrowserEngineEvent event) => _events.add(event);

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  Future<void> load(Uri url) async => loads.add(url);
  @override
  Future<void> goBack() async => calls.add('back');
  @override
  Future<void> goForward() async => calls.add('forward');
  @override
  Future<void> reload() async => calls.add('reload');
  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> runScript(String script) async {
    await scriptGate?.future;
    if (scriptError != null) throw scriptError!;
    scripts.add(script);
  }

  @override
  Future<Uint8List> capturePng() async {
    onCapture?.call();
    return png;
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async =>
      forwarded = chords;

  @override
  Future<void> focusContent() async => calls.add('focus');

  @override
  Future<void> releaseFocus() async => calls.add('release');

  @override
  Widget buildView() => const SizedBox.expand(key: Key('browser.fakeView'));

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
