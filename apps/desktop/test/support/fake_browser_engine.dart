import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:shellx_desktop/src/browser/browser_engine.dart';

/// Test double: records calls, lets tests push engine events.
final class FakeBrowserEngine implements BrowserEngine {
  FakeBrowserEngine({this.coversFlutter = false, this.key = 'fake'});

  /// Tells engines apart in widget keys (`browser.fakeView.<key>`).
  final String key;

  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast(sync: true);

  @override
  final bool coversFlutter;

  final List<Uri> loads = [];
  final List<String> calls = [];
  List<String> forwarded = const [];
  bool? visible;
  bool disposed = false;

  /// How many times [buildView] ran (a rebuilt platform view would be a
  /// second native view for one page).
  int builds = 0;

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
  Future<void> setForwardedChords(List<String> chords) async =>
      forwarded = chords;

  @override
  Future<void> focusContent() async => calls.add('focus');

  @override
  Future<void> releaseFocus() async => calls.add('release');

  @override
  Future<void> setVisible(bool visible) async => this.visible = visible;

  @override
  Widget buildView() {
    builds++;
    return SizedBox.expand(key: Key('browser.fakeView.$key'));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
