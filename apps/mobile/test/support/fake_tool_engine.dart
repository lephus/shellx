import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

/// Stands for the web view of a tool page (V2-4): records what the page asks of it; a test plays
/// the web view's side through [callbacks]. A tool page makes a fresh one for a serve on other origins
/// ([FakeToolWebEngines]).
class FakeToolWebEngine implements ToolWebEngine {
  FakeToolWebEngine({this.name = 'web', List<String>? log}) : log = log ?? [];

  /// Which web view this is ("web1", "web2" …), and the log shared by every web view of one
  /// [FakeToolWebEngines]: what each was asked, in order.
  final String name;
  final List<String> log;
  late ToolWebCallbacks callbacks;
  late Future<void> Function(Uri url) ask;
  final List<Uri> loads = [];
  int reloads = 0;
  int goBacks = 0;
  bool canGoBackValue = false;
  bool disposed = false;

  /// How many times its view was put on screen from scratch: a platform view is never reused by
  /// another web view, so each web view's view is built once.
  int viewStates = 0;

  @override
  void attach(ToolWebCallbacks callbacks) => this.callbacks = callbacks;

  @override
  set askExternal(Future<void> Function(Uri url) ask) => this.ask = ask;

  @override
  Future<void> load(Uri url) async {
    loads.add(url);
    log.add('$name load ${url.scheme == 'about' ? url : '${url.host}:${url.port}${url.path}'}');
  }

  @override
  Future<void> reload() async {
    reloads++;
    log.add('$name reload');
  }

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<void> goBack() async => goBacks++;

  @override
  Widget view() => _FakeView(key: const Key('fake-webview'), engine: this);

  @override
  void dispose() {
    disposed = true;
    log.add('$name dispose');
  }
}

/// Hands out a new [FakeToolWebEngine] each time the tool page asks for a web view (V2-4 NB1: a serve on
/// other origins gets a fresh one), and remembers them in order, with one log of what they were all asked.
class FakeToolWebEngines {
  final List<FakeToolWebEngine> made = [];
  final List<String> log = [];

  FakeToolWebEngine next() {
    final engine = FakeToolWebEngine(name: 'web${made.length + 1}', log: log);
    made.add(engine);
    return engine;
  }

  /// The web view the page shows now: the last one made.
  FakeToolWebEngine get current => made.last;
}

class _FakeView extends StatefulWidget {
  const _FakeView({super.key, required this.engine});

  final FakeToolWebEngine engine;

  @override
  State<_FakeView> createState() => _FakeViewState();
}

class _FakeViewState extends State<_FakeView> {
  @override
  void initState() {
    super.initState();
    widget.engine.viewStates++;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xFFFFFFFF), child: Text(widget.engine.name));
}

/// Records what Settings clears.
class FakeToolWebData implements ToolWebData {
  int clears = 0;

  @override
  Future<void> clear() async => clears++;
}
