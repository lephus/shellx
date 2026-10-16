import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/controllers/tool_page_controller.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_tool_engine.dart';
import '../../support/fakes.dart';

const _tool = ToolInfo(id: 'k3f9za7q1m', name: 'Bảng việc', ws: 'shop-web', port: 5173, path: '/', group: 'ws:a');

/// The web views the page asked for, in order (a serve on other origins gets a fresh one).
late FakeToolWebEngines engines;

/// The web view the page shows now.
FakeToolWebEngine get engine => engines.current;

/// V2-4 E12, E13, E15, E16, E20: the tool page with a stand-in web view.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakePopupHandler popups;
  late FakeExternalLinks links;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    final session = FakeSessionHolder(backend);
    engines = FakeToolWebEngines();
    popups = FakePopupHandler();
    links = FakeExternalLinks();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<ToolWebEngine>(engines.next)
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

  /// The app goes to the background (E13): the session is told to stop serving.
  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  /// The app is back on screen: the session is told to serve again.
  Future<void> foreground(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
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
    expect(engines.made, hasLength(1), reason: 'the first entry load uses the web view the page started with');
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

  // S2: this phone could hold no port on every loopback address it has; tried again by itself, like refused.
  testWidgets('no port on the phone (S2): its own text over the page, with the spinner', (tester) async {
    await open(tester);
    page().setPhase(ToolPhase.noPort);
    await tester.pump();
    final cover = find.byKey(const Key('tool.noPort'));
    expect(cover, findsOneWidget);
    expect(
      find.descendant(of: cover, matching: find.text('Điện thoại không mở được cổng cục bộ cho tool.')),
      findsOneWidget,
    );
    expect(find.descendant(of: cover, matching: find.byType(AppCircularProgress)), findsOneWidget);
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

  // Task 13 (L476): each load starts its progress line at 0, not at the last page's 100 %.
  testWidgets('each page start begins the progress line at 0', (tester) async {
    await open(tester);
    await shown(tester);
    engine.callbacks.onPageStarted();
    engine.callbacks.onProgress(100);
    engine.callbacks.onPageFinished();
    await tester.pump();
    engine.callbacks.onPageStarted();
    await tester.pump();
    final line = tester.widget<LinearProgressIndicator>(find.byKey(const Key('tool.progress')));
    expect(line.value, 0);
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

  // C1: on Android the plugin loads whatever the policy lets through, and a link the web view will not
  // render (a download, a PDF) comes back to the same policy; let through again, it goes round for ever.
  // iOS has no such loop (WebKit never re-enters the policy for a download), so the guard is Android's.
  const download = 'http://localhost:5173/files/report.zip';
  const manual = 'http://localhost:5173/manual.pdf#page=4';
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets(
    'an address let through that comes back before any page start is a download: stopped, one toast (C1)',
    (tester) async {
      await open(tester);
      await shown(tester);
      expect(engine.callbacks.decide(download, true), isA<ToolGo>());
      expect(engine.callbacks.decide(download, true), isA<ToolBlock>());
      expect(popups.infos, ['Tải tệp chưa làm được trên điện thoại.']);
    },
    variant: android,
  );

  testWidgets('a PDF address with a fragment is a download too: stopped, one toast (C1)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide(manual, true), isA<ToolGo>());
    expect(engine.callbacks.decide(manual, true), isA<ToolBlock>());
    expect(popups.infos, ['Tải tệp chưa làm được trên điện thoại.']);
  }, variant: android);

  testWidgets('after a page start the same address goes on again (C1)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    engine.callbacks.onPageStarted();
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    expect(popups.infos, isEmpty);
  }, variant: android);

  testWidgets('a page started twice and never finished that comes back a third time is a download too (C1)', (
    tester,
  ) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    engine.callbacks.onPageStarted();
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    engine.callbacks.onPageStarted();
    expect(engine.callbacks.decide(download, true), isA<ToolBlock>());
    expect(popups.infos, ['Tải tệp chưa làm được trên điện thoại.']);
  }, variant: android);

  testWidgets('a finished page forgets what it let through: a reload after a redirect goes on (C1)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide('http://localhost:5173/__shellx/enter?n=x', true), isA<ToolGo>());
    engine.callbacks.onPageStarted();
    expect(engine.callbacks.decide('http://localhost:5173/', true), isA<ToolGo>());
    engine.callbacks.onPageFinished();
    expect(engine.callbacks.decide('http://localhost:5173/', true), isA<ToolGo>());
    expect(popups.infos, isEmpty);
  }, variant: android);

  testWidgets('frames and about:blank are never stopped (C1)', (tester) async {
    await open(tester);
    await shown(tester);
    for (final (url, mainFrame) in [(download, false), (manual, false), ('about:blank', true)]) {
      for (var i = 0; i < 4; i++) {
        expect(engine.callbacks.decide(url, mainFrame), isA<ToolGo>(), reason: '$url, time $i');
      }
    }
    expect(popups.infos, isEmpty);
  }, variant: android);

  testWidgets('a load the app makes itself is no re-entry (C1)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    await tester.tap(find.byKey(const Key('tool.reload')));
    await tester.pump();
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    page().emit(const ToolReload());
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    expect(popups.infos, isEmpty);
  }, variant: android);

  testWidgets('on iOS there is no guard: WebKit asks the policy for a #/route link again and again (C1)', (
    tester,
  ) async {
    await open(tester);
    await shown(tester);
    for (final url in [download, manual, 'http://localhost:5173/#/board']) {
      for (var i = 0; i < 4; i++) {
        expect(engine.callbacks.decide(url, true), isA<ToolGo>(), reason: '$url, time $i');
      }
    }
    expect(popups.infos, isEmpty);
  }, variant: ios);

  // I3: iOS reports a page that failed to load only as an error and never as finished.
  testWidgets('a page that fails to load ends the load: no progress line, no slow line, no cover (I3)', (
    tester,
  ) async {
    await open(tester);
    page().ready();
    engine.callbacks.onPageStarted();
    await tester.pump();
    expect(find.byKey(const Key('tool.progress')), findsOneWidget);
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget, reason: 'the first load');
    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.byKey(const Key('tool.slow')), findsOneWidget);
    engine.callbacks.onLoadError(true);
    await tester.pump();
    expect(find.byKey(const Key('tool.progress')), findsNothing);
    expect(find.byKey(const Key('tool.slow')), findsNothing);
    expect(find.text('Đang tải qua đường hầm…'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('tool.slow')), findsNothing, reason: 'the timer of the slow line is gone');
  });

  testWidgets('an error inside the page changes nothing (I3)', (tester) async {
    await open(tester);
    await shown(tester);
    engine.callbacks.onPageStarted();
    await tester.pump(const Duration(milliseconds: 3600));
    engine.callbacks.onLoadError(false);
    await tester.pump();
    expect(find.byKey(const Key('tool.progress')), findsOneWidget);
    expect(find.byKey(const Key('tool.slow')), findsOneWidget);
  });

  testWidgets('a page that failed to load forgets what it let through (I3, C1)', (tester) async {
    await open(tester);
    await shown(tester);
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    engine.callbacks.onLoadError(true);
    expect(engine.callbacks.decide(download, true), isA<ToolGo>());
    expect(popups.infos, isEmpty);
  }, variant: android);

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
    await background(tester);
    expect(page().pauses, 1);
    await foreground(tester);
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

  // I1: Android's web view never hands "back" to the navigation policy, so the page only walks its
  // history while it is shown and while that history is of one port.
  testWidgets('back goes back in the page under the reconnecting strip while the session serves (I1)', (
    tester,
  ) async {
    await open(tester);
    await shown(tester);
    page().setPhase(ToolPhase.reconnecting);
    await tester.pump();
    engine.canGoBackValue = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(engine.goBacks, 1);
    expect(find.text('Bảng việc'), findsOneWidget);
    expect(page().closes, 0);
  });

  for (final phase in [
    ToolPhase.opening,
    ToolPhase.busy,
    ToolPhase.refused,
    ToolPhase.noPort,
    ToolPhase.disabled,
    ToolPhase.gone,
    ToolPhase.unavailable,
  ]) {
    testWidgets('back leaves the page while a ${phase.name} cover hides it: the hidden history is not walked (I1)', (
      tester,
    ) async {
      await open(tester);
      await shown(tester);
      page().setPhase(phase);
      await tester.pump();
      engine.canGoBackValue = true;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(engine.goBacks, 0);
      expect(find.text('Bảng việc'), findsNothing);
      expect(page().closes, 1);
    });
  }

  // Task 13 (b): under the first-load cover the page is not shown yet, and its history may hold the blank of an
  // earlier serve (A): back leaves the page instead of walking it.
  testWidgets('back during the first load leaves the page: the hidden history is not walked', (tester) async {
    await open(tester);
    page().ready(); // the entry loads under the first-load cover
    await tester.pump();
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget);
    engine.canGoBackValue = true;
    await tester.binding.handlePopRoute();
    await tester.pump(); // the decision (the cover's spinner settles only once the page has left)
    expect(engine.goBacks, 0);
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc'), findsNothing);
    expect(page().closes, 1);
  });

  testWidgets('back leaves after a re-serve on another port: the fresh web view has no history (NB1)', (tester) async {
    await open(tester);
    await shown(tester);
    final first = engine;
    first.canGoBackValue = true; // pages of the old port, which another app may hold by now
    page().ready(port: 49152);
    await tester.pump();
    engine.callbacks.onPageStarted();
    engine.callbacks.onPageFinished();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(first.goBacks, 0);
    expect(engine.goBacks, 0);
    expect(find.text('Bảng việc'), findsNothing);
    expect(page().closes, 1);
    expect(engines.made.map((web) => web.disposed), [true, true], reason: 'leaving disposes the web view it shows');
  });

  // NB2: the strip lifts a cover once the link drops, but with the servers closed (after "disabled", "gone",
  // "unavailable", or a lost channel right after a resume) the history points at ports nothing of ours serves.
  testWidgets('back leaves the page while reconnecting with nothing served (NB2)', (tester) async {
    await open(tester);
    await shown(tester);
    page().servedPortValue = null;
    page().setPhase(ToolPhase.reconnecting);
    await tester.pump();
    engine.canGoBackValue = true;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(engine.goBacks, 0);
    expect(find.text('Bảng việc'), findsNothing);
    expect(page().closes, 1);
  });

  // NB1: every serve (a first serve or a re-serve) has a new secret, and cookies ignore ports: a serve on other
  // origins than the web view was opened for gets a fresh one, so the history of a serve on other ports is never
  // there to walk (by the user's back, or by the page's own history.back()), and the old page's scripts stop before
  // the new entry sets the new cookie. A serve on the same origins keeps it (A).
  testWidgets('"Về trang đầu" and a reload keep the web view: only a serve on other origins gets a new one (NB1)', (
    tester,
  ) async {
    await open(tester);
    await shown(tester);
    page().emit(ToolLoad(Uri.parse('http://localhost:5173/'))); // the start page: not an entry URL
    page().emit(const ToolReload());
    await tester.pump();
    expect(engines.made, hasLength(1));
    expect(engines.log, ['web1 load localhost:5173/__shellx/enter', 'web1 load localhost:5173/', 'web1 reload']);
  });

  testWidgets(
    'a re-serve gets a web view of its own: the old one goes blank first, then the entry loads in a fresh one (NB1)',
    (
      tester,
    ) async {
      await open(tester);
      await shown(tester);
      final first = engine;
      page().ready(port: 49152);
      await tester.pump();
      expect(engines.made, hasLength(2));
      expect(engines.log, [
        'web1 load localhost:5173/__shellx/enter',
        'web1 load about:blank',
        'web1 dispose',
        'web2 load localhost:49152/__shellx/enter',
      ]);
      expect(first.disposed, isTrue);
      expect(engine.disposed, isFalse);
      expect(engines.made.map((web) => web.viewStates), [1, 1], reason: 'a platform view is never reused');
      expect(find.text('web2'), findsOneWidget);
      expect(find.text('web1'), findsNothing);
    },
  );

  testWidgets('pausing blanks the web view; the next serve gets a fresh one (E13, NB1)', (tester) async {
    await open(tester);
    await shown(tester);
    await background(tester);
    expect(page().pauses, 1);
    expect(engines.log.last, 'web1 load about:blank');
    await foreground(tester);
    expect(page().resumes, 1);
    page().ready(port: 49152); // served again, on another port: a new secret and its entry URL
    await tester.pump();
    expect(engines.made, hasLength(2));
    expect(engines.made.first.disposed, isTrue);
    expect(engine.loads.single.port, 49152);
  });

  // A: a serve that comes back on the same ports loads its entry in the web view that is there, so that its
  // sessionStorage and its in-page history stay (a tool that keeps its token there is not signed out at every app
  // switch): every page of that history is on a port served again by this session. Other ports, or a sibling
  // missing or new, are another set: a fresh web view.
  testWidgets('served again on the same ports after a pause, the entry loads in the same web view (A)', (
    tester,
  ) async {
    await open(tester);
    page().siblingPorts.add(8000);
    await shown(tester);
    await background(tester);
    await foreground(tester);
    page().ready(); // the same ports again: a new secret, a new entry URL
    await tester.pump();
    expect(engines.made, hasLength(1));
    expect(engines.log, [
      'web1 load localhost:5173/__shellx/enter',
      'web1 load about:blank',
      'web1 load localhost:5173/__shellx/enter',
    ]);
    expect(find.text('Đang tải qua đường hầm…'), findsOneWidget, reason: 'covered again until the entry page is in');
    engine.callbacks.onPageStarted();
    engine.callbacks.onPageFinished();
    await tester.pump();
    expect(find.text('Đang tải qua đường hầm…'), findsNothing);
  });

  testWidgets('a sibling no longer served is another set: a fresh web view, the old one blanked first (A)', (
    tester,
  ) async {
    await open(tester);
    page().siblingPorts.add(8000);
    await shown(tester);
    await background(tester);
    await foreground(tester);
    page().siblingPorts.clear(); // another app holds the sibling's port now
    page().ready();
    await tester.pump();
    expect(engines.made, hasLength(2));
    expect(engines.log, [
      'web1 load localhost:5173/__shellx/enter',
      'web1 load about:blank',
      'web1 load about:blank',
      'web1 dispose',
      'web2 load localhost:5173/__shellx/enter',
    ]);
  });

  testWidgets('a sibling that is served now is another set too (A)', (tester) async {
    await open(tester);
    await shown(tester);
    await background(tester);
    await foreground(tester);
    page().siblingPorts.add(8000);
    page().ready();
    await tester.pump();
    expect(engines.made, hasLength(2));
    expect(engines.made.first.disposed, isTrue);
  });

  testWidgets('the set that counts is the one the current web view was opened for (A)', (tester) async {
    await open(tester);
    await shown(tester);
    page().ready(port: 49152); // another port: web2, opened for 49152
    await tester.pump();
    await background(tester);
    await foreground(tester);
    page().ready(port: 49152); // the ports web2 was opened for, again: web2 again
    await tester.pump();
    expect(engines.made, hasLength(2));
    expect(engines.made.last.loads.where((url) => url.scheme == 'http').map((url) => url.port), [49152, 49152]);
    expect(engines.made.first.disposed, isTrue);
    expect(engines.made.last.disposed, isFalse);
  });

  // B: the page stops with the servers. Leaving the page, and the servers closing while the page stays, send the
  // web view to about:blank, so that its scripts do not go on asking ports nothing of ours serves, with the cookies
  // of every port (once the user opens a tool again, those include a live secret).
  testWidgets('leaving the page sends the web view to about:blank before it is dropped (B)', (tester) async {
    await open(tester);
    await shown(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc'), findsNothing);
    expect(engines.log, ['web1 load localhost:5173/__shellx/enter', 'web1 load about:blank', 'web1 dispose']);
  });

  testWidgets('leaving a page nothing was loaded in leaves the blank web view alone (B)', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('tool.back')));
    await tester.pumpAndSettle();
    expect(find.text('Bảng việc'), findsNothing);
    expect(engines.log, ['web1 dispose']);
  });

  for (final phase in [ToolPhase.disabled, ToolPhase.gone, ToolPhase.unavailable]) {
    testWidgets(
      'the servers closing (${phase.name}) send the web view to about:blank, once; served again, it takes the entry (B)',
      (tester) async {
        await open(tester);
        await shown(tester);
        page().servedPortValue = null; // the servers are closed
        page().setPhase(phase);
        await tester.pump();
        expect(engines.log, ['web1 load localhost:5173/__shellx/enter', 'web1 load about:blank']);
        page().setPhase(phase); // told again: not blanked again
        await tester.pump();
        expect(engines.log, hasLength(2));
        page().ready(); // served again on the same port: the same web view, per rule A
        await tester.pump();
        expect(engines.made, hasLength(1));
        expect(engines.log.last, 'web1 load localhost:5173/__shellx/enter');
      },
    );
  }

  testWidgets('the servers closing in one phase after another blank the web view once (B)', (tester) async {
    await open(tester);
    await shown(tester);
    page().servedPortValue = null;
    page().setPhase(ToolPhase.disabled);
    page().setPhase(ToolPhase.gone);
    page().setPhase(ToolPhase.unavailable);
    await tester.pump();
    expect(engines.log.where((entry) => entry == 'web1 load about:blank'), hasLength(1));
  });

  // noPort (S2): nothing was served, or the web view is blank already: entering it blanks nothing.
  for (final phase in [
    ToolPhase.opening,
    ToolPhase.busy,
    ToolPhase.refused,
    ToolPhase.noPort,
    ToolPhase.reconnecting,
  ]) {
    testWidgets('the servers staying open (${phase.name}) leave the web view alone (B)', (tester) async {
      await open(tester);
      await shown(tester);
      page().setPhase(phase);
      await tester.pump();
      expect(engines.log, ['web1 load localhost:5173/__shellx/enter']);
    });
  }

  // Leaving raises the generation: what the left web view reports after that is not heard.
  testWidgets('after leaving, a late question of the left web view touches no closed stream (B)', (tester) async {
    await open(tester);
    await shown(tester);
    final left = engine;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // Heard, an unserved local port would be named in a toast: an add on the closed notices (a StateError inside
    // the plugin's callback).
    expect(left.callbacks.decide('http://localhost:8000/', true), isA<ToolBlock>());
    left.callbacks.onFileChooser();
    expect(popups.infos, isEmpty);
  });

  testWidgets('after leaving, a late page start of the left web view starts no timer (B)', (tester) async {
    await open(tester);
    await shown(tester);
    final left = engine;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    left.callbacks.onPageStarted(); // heard, it would start a periodic timer that nothing cancels
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a pause before anything is loaded leaves the blank web view alone (NB1)', (tester) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(page().pauses, 1);
    expect(engines.log, isEmpty);
  });

  testWidgets(
    'what a retired web view reports is ignored: its page finishing does not lift the cover of the new one (NB1)',
    (
      tester,
    ) async {
      await open(tester);
      await shown(tester);
      final retired = engine;
      page().ready(port: 49152);
      await tester.pump();
      expect(find.text('Đang tải qua đường hầm…'), findsOneWidget, reason: 'the fresh web view has no page yet');
      retired.callbacks.onPageStarted();
      retired.callbacks.onProgress(50);
      retired.callbacks.onPageFinished();
      retired.callbacks.onLoadError(true);
      retired.callbacks.onCrashed();
      retired.callbacks.onFileChooser();
      await tester.pump();
      expect(find.text('Đang tải qua đường hầm…'), findsOneWidget);
      expect(find.byKey(const Key('tool.progress')), findsNothing);
      expect(retired.reloads, 0);
      expect(popups.infos, isEmpty);
      // It may only go blank, and it shows nothing.
      expect(retired.callbacks.decide('about:blank', true), isA<ToolGo>());
      expect(retired.callbacks.decide('http://localhost:5173/x', true), isA<ToolBlock>());
      expect(retired.callbacks.decide('http://localhost:49152/x', true), isA<ToolBlock>());
      expect(retired.callbacks.decide('https://accounts.example.com/sso', true), isA<ToolBlock>());
      await retired.callbacks.alert('hi');
      expect(await retired.callbacks.confirm('sure?'), isFalse);
      expect(await retired.callbacks.prompt('name?', 'An'), isNull);
      expect(find.byKey(const Key('tool.dialog')), findsNothing);
      expect(popups.infos, isEmpty);
      // The page of the fresh web view lifts the cover.
      engine.callbacks.onPageStarted();
      engine.callbacks.onPageFinished();
      await tester.pump();
      expect(find.text('Đang tải qua đường hầm…'), findsNothing);
    },
  );

  testWidgets('a fresh web view starts with nothing loading: no progress line, no slow line, no timer (NB1)', (
    tester,
  ) async {
    await open(tester);
    await shown(tester);
    engine.callbacks.onPageStarted();
    await tester.pump(const Duration(milliseconds: 3600));
    expect(find.byKey(const Key('tool.progress')), findsOneWidget);
    expect(find.byKey(const Key('tool.slow')), findsOneWidget);
    page().ready(port: 49152);
    await tester.pump();
    expect(find.byKey(const Key('tool.progress')), findsNothing);
    expect(find.byKey(const Key('tool.slow')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('tool.slow')), findsNothing, reason: 'the old web view\'s timer is gone');
  });

  testWidgets(
    'the fresh web view is wired like the first: it asks before another site opens, its dialogs are the app\'s (NB1)',
    (
      tester,
    ) async {
      await open(tester);
      await shown(tester);
      page().ready(port: 49152);
      await tester.pump();
      engine.callbacks.onPageStarted();
      engine.callbacks.onPageFinished();
      await tester.pumpAndSettle();
      final decision = engine.callbacks.decide('https://accounts.example.com/sso', true);
      expect(decision, isA<ToolAskExternal>());
      unawaited(engine.ask((decision as ToolAskExternal).url));
      await tester.pumpAndSettle();
      expect(find.text('Mở accounts.example.com bằng trình duyệt?'), findsOneWidget);
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      expect(links.opened.single.toString(), 'https://accounts.example.com/sso');
      final confirmed = engine.callbacks.confirm('Xóa thẻ?');
      await tester.pumpAndSettle();
      expect(find.text('Bảng việc nhắn'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await confirmed, isTrue);
    },
  );
}
