import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

/// Stands for the web view of a tool page (V2-4): records what the page asks of it; a test plays
/// the web view's side through [callbacks].
class FakeToolWebEngine implements ToolWebEngine {
  late ToolWebCallbacks callbacks;
  late Future<void> Function(Uri url) ask;
  final List<Uri> loads = [];
  int reloads = 0;
  int goBacks = 0;
  bool canGoBackValue = false;
  bool disposed = false;

  @override
  void attach(ToolWebCallbacks callbacks) => this.callbacks = callbacks;

  @override
  set askExternal(Future<void> Function(Uri url) ask) => this.ask = ask;

  @override
  Future<void> load(Uri url) async => loads.add(url);

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<void> goBack() async => goBacks++;

  @override
  Widget view() => const ColoredBox(key: Key('fake-webview'), color: Color(0xFFFFFFFF));

  @override
  void dispose() => disposed = true;
}

/// Records what Settings clears.
class FakeToolWebData implements ToolWebData {
  int clears = 0;

  @override
  Future<void> clear() async => clears++;
}
