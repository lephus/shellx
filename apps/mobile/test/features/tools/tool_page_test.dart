import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/controllers/tool_page_controller.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_tool_engine.dart';
import '../../support/fakes.dart';

const _tool = ToolInfo(id: 'k3f9za7q1m', name: 'Bảng việc', ws: 'shop-web', port: 5173, path: '/', group: 'ws:a');

/// V2-4 E12, E13, E15, E16, E20: the tool page with a stand-in web view.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeToolWebEngine engine;
  late FakePopupHandler popups;
  late FakeExternalLinks links;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    engine = FakeToolWebEngine();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<ToolWebEngine>(() => engine)
      ..registerFactoryParam<ToolPageController, String, ToolInfo>(
        (agentId, tool) => ToolPageController(agentId, tool, session),
      );
  });

  tearDown(() => getIt.reset());

  FakeToolPage page() => machine.tools.pages.single;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => ToolRoute(agentId: agentA, tool: _tool),
        routes: [AutoRoute(page: ToolRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    // The first load shows a spinner: pump the push, never settle it.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The tool is served and its first page is in (no spinner left).
  Future<void> shown(WidgetTester tester, {int? port}) async {
    page().ready(port: port);
    engine.callbacks.onPageStarted();
    engine.callbacks.onPageFinished();
    await tester.pumpAndSettle();
  }

  testWidgets('the bar names the tool; first load through the tunnel, then the page', (tester) async {
    await open(tester);
    expect(page().starts, 1);
    // The phone server's own answers are in the phone's language.
    final texts = machine.tools.texts.single;
    expect(texts.refused(5173), 'Không có gì chạy ở localhost:5173 trên máy tính.');
    expect(texts.siblingOff(8000), 'Tool ở cổng 8000 chưa bật cho điện thoại.');
    expect(texts.tooLarge, 'Phản hồi của tool quá lớn.');
    expect(find.text('Bảng việc'), findsOneWidget);
    expect(find.text('localhost:5173 · qua máy tính'), findsOneWidget);
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget);
    page().ready();
    await tester.pump();
    expect(engine.loads.single.path, '/__shellx/enter');
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget, reason: 'until the first page is in');
    engine.callbacks.onPageStarted();
    engine.callbacks.onProgress(40);
    engine.callbacks.onPageFinished();
    await tester.pump();
    expect(find.text('Đang tải qua đường hầm…'), findsNothing);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);
  });

  testWidgets('the states of E16 cover the page', (tester) async {
    await open(tester);
    await shown(tester);
    for (final (phase, text) in [
      (ToolPhase.refused, 'Không có gì chạy ở localhost:5173 trên máy tính.'),
      (ToolPhase.disabled, 'Tool này không còn mở được trên điện thoại.'),
      (ToolPhase.gone, 'Tool này đã bị xóa trên máy tính.'),
      (ToolPhase.unavailable, 'Mở ShellX trên máy tính để dùng tool.'),
    ]) {
      page().setPhase(phase);
      await tester.pump();
      expect(find.text(text), findsOneWidget, reason: phase.name);
    }
  });

  testWidgets('a lost channel keeps the page under "Đang kết nối lại…"; another port says so (E3)', (tester) async {
    await open(tester);
    await shown(tester, port: 49152);
    expect(
      find.text('Đang mở ở cổng 49152 vì cổng 5173 bận trên điện thoại. Link ghi rõ cổng 5173 có thể không chạy.'),
      findsOneWidget,
    );
    page().setPhase(ToolPhase.reconnecting);
    await tester.pump();
    expect(find.text('Đang kết nối lại…'), findsOneWidget);
    expect(find.byKey(const Key('fake-webview')), findsOneWidget);
    page().emit(const ToolReload());
    expect(engine.reloads, 1);
  });

  testWidgets('↻ reloads; ⋯ goes to the start page or reloads', (tester) async {
    await open(tester);
    await shown(tester);
    await tester.tap(find.byKey(const Key('tool.reload')));
    await tester.pump();
    expect(engine.reloads, 1);
    await tester.tap(find.byKey(const Key('tool.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Về trang đầu'));
    await tester.pumpAndSettle();
    expect(page().homes, 1);
    await tester.tap(find.byKey(const Key('tool.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tool.menuReload')));
    await tester.pumpAndSettle();
    expect(engine.reloads, 2);
  });

  testWidgets('past 3 s a page says how many requests it made (E20)', (tester) async {
    await open(tester);
    await shown(tester);
    engine.callbacks.onPageStarted();
    page().requestsValue = 7;
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('tool.slow')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Đang tải qua máy tính… (7 request)'), findsOneWidget);
    engine.callbacks.onPageFinished();
    await tester.pump();
    expect(find.byKey(const Key('tool.slow')), findsNothing);
  });

  testWidgets('another site asks first, then opens in the browser (E12)', (tester) async {
    await open(tester);
    await shown(tester);
    final decision = engine.callbacks.decide('https://accounts.example.com/sso', true);
    expect(decision, isA<ToolAskExternal>());
    unawaited(engine.ask((decision as ToolAskExternal).url));
    await tester.pumpAndSettle();
    expect(find.text('Mở accounts.example.com bằng trình duyệt?'), findsOneWidget);
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(links.opened.single.toString(), 'https://accounts.example.com/sso');
    expect(engine.callbacks.decide('http://localhost:5173/x', true), isA<ToolGo>());
    expect(engine.callbacks.decide('javascript:alert(1)', true), isA<ToolBlock>());
  });

  testWidgets('a local port that is not served is named in a toast (E4)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide('http://localhost:8000/', true), isA<ToolOtherLocal>());
    expect(popups.infos.single, 'Tool ở cổng 8000 chưa bật cho điện thoại.');
  });

  testWidgets('the page\'s dialogs are the app\'s and name the tool (E12)', (tester) async {
    await open(tester);
    await shown(tester);
    final confirmed = engine.callbacks.confirm('Xóa thẻ?');
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc nhắn'), findsOneWidget);
    expect(find.text('Xóa thẻ?'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await confirmed, isTrue);
    final typed = engine.callbacks.prompt('Tên?', 'An');
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc nhắn'), findsOneWidget);
    expect(find.text('Tên?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tool.dialogField')), 'Bình');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(await typed, 'Bình');
    // The third kind is titled with the tool's name too.
    final alerted = engine.callbacks.alert('Đã lưu.');
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc nhắn'), findsOneWidget);
    expect(find.text('Đã lưu.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await alerted;
  });

  testWidgets('downloads and file choosers are not on the phone yet: a toast (E12)', (tester) async {
    await open(tester);
    page().emit(const ToolDownloadBlocked());
    engine.callbacks.onFileChooser();
    page().emit(const ToolSiblingOff(8000));
    expect(popups.infos, [
      'Tải tệp chưa làm được trên điện thoại.',
      'Tải tệp chưa làm được trên điện thoại.',
      'Tool ở cổng 8000 chưa bật cho điện thoại.',
    ]);
  });

  testWidgets('the app in the background: nothing served; back: served again (E13); a stopped web '
      'process reloads', (tester) async {
    await open(tester);
    await shown(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(page().pauses, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(page().resumes, 1);
    engine.callbacks.onCrashed();
    expect(engine.reloads, 1);
  });

  testWidgets('back goes back in the page first, then leaves; leaving closes the tool', (tester) async {
    await open(tester);
    await shown(tester);
    engine.canGoBackValue = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(engine.goBacks, 1);
    expect(find.text('Bảng việc'), findsOneWidget);
    engine.canGoBackValue = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc'), findsNothing);
    expect(page().closes, 1);
    expect(engine.disposed, isTrue);
  });
}
