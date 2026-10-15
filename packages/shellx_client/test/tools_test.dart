import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

/// Records what phones send; says what a test makes it say.
final class _Spy implements ToolEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final handled = <ToolMessage>[];

  void say(ToolMessage m) => _out.add(OutboundMessage(phoneId, m));

  @override
  Stream<OutboundMessage> get outbound => _out.stream;
  @override
  bool get serving => true;
  @override
  void handle(String mobileId, ToolMessage message) => handled.add(message);
  @override
  void phoneGone(String mobileId) {}
  @override
  void allPhonesGone() {}
}

/// Records what a stream hears.
final class _Listener implements ToolStreamListener {
  final heard = <String>[];
  @override
  void onResponse(ToolResponse message) => heard.add('response');
  @override
  void onData(ToolData message) => heard.add('data');
  @override
  void onWsMessage(ToolWsMessage message) => heard.add('ws');
  @override
  void onAck(int total) => heard.add('ack $total');
  @override
  void onEnd(ToolEnd message) => heard.add('end ${message.code}');
  @override
  void onLost() => heard.add('lost');
}

ToolCatalog _catalog() => ToolCatalog.fromServeBody(
  ToolCatalog.serveBody([
    {
      'id': 'k3f9za7q1m',
      'name': 'Bảng việc',
      'ws': 'shop-web',
      'group': 'ws:a',
      'url': 'http://localhost:5173/app',
    },
  ]),
)!;

int _framesFromPhone(Harness h) =>
    h.relay.delivered.where((d) => d.from == phoneId).length;

/// V2-4 E6, E8, E19: the phone's `MachineTools` over the real encrypted
/// channel and the fake relay.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('the tools flag, the list and its changes, and an open', () {
    fakeAsync((async) {
      final proxy = ToolProxy()..serve(_catalog());
      final h = Harness(async, keys, tools: proxy);
      final tools = h.phoneMachine.tools;
      h.run(h.phoneMachine.listSessions(includeDesktop: true));
      expect(tools.supported, isTrue);
      h.run(tools.watch());
      settle(async);
      final tool = tools.listing!.tools.single;
      expect(tool.name, 'Bảng việc');
      expect(tool.port, 5173);
      expect(tool.path, '/app');
      expect(tool.ws, 'shop-web');
      proxy.serve(ToolCatalog([]));
      settle(async);
      expect(tools.listing!.tools, isEmpty);
      final opened = h.run(tools.open('unknown111'));
      expect(opened.ok, isFalse);
      expect(opened.code, 'gone');
      proxy.close();
    });
  });

  test('tool messages within 16 ms go in one frame; acks of every stream in '
      'one tool.ack per 50 ms (E8)', () {
    fakeAsync((async) {
      final spy = _Spy();
      final h = Harness(async, keys, tools: spy);
      final tools = h.phoneMachine.tools;
      h.run(h.phoneMachine.connect());
      settle(async);
      final before = _framesFromPhone(h);
      tools.enqueue(const ToolEnd(id: 1, code: 'aborted'));
      async.elapse(const Duration(milliseconds: 5));
      tools.enqueue(const ToolEnd(id: 2, code: 'aborted'));
      tools.enqueue(const ToolClose(tool: 'k3f9za7q1m'));
      async.elapse(const Duration(milliseconds: 11));
      settle(async);
      expect(_framesFromPhone(h) - before, 1);
      expect(spy.handled.map((m) => m.type), [
        'tool.end',
        'tool.end',
        'tool.close',
      ]);

      tools.acks.consumed(7, 100);
      tools.acks.consumed(8, 50);
      tools.acks.consumed(7, 300);
      async.elapse(const Duration(milliseconds: 49));
      expect(spy.handled.whereType<ToolAck>(), isEmpty);
      settle(async);
      expect(spy.handled.whereType<ToolAck>().single.acks, [7, 300, 8, 50]);
    });
  });

  test('at most 100 tool frames a second, in order, none lost (E8, RF 2)', () {
    fakeAsync((async) {
      final spy = _Spy();
      final h = Harness(async, keys, tools: spy);
      final tools = h.phoneMachine.tools;
      h.run(h.phoneMachine.connect());
      settle(async);
      final before = _framesFromPhone(h);
      for (var i = 0; i < 250; i++) {
        tools.enqueue(
          ToolData(id: i, data: Uint8List(kToolMaxChunkBytes), end: false),
        );
      }
      async.elapse(const Duration(seconds: 1));
      expect(_framesFromPhone(h) - before, lessThanOrEqualTo(10 + 100));
      async.elapse(const Duration(seconds: 2));
      settle(async);
      expect(_framesFromPhone(h) - before, 250);
      expect(
        [for (final m in spy.handled.whereType<ToolData>()) m.id],
        [for (var i = 0; i < 250; i++) i],
      );
    });
  });

  test(
    'a message over one sealed batch is refused; the channel stays (RF 1)',
    () {
      fakeAsync((async) {
        final spy = _Spy();
        final h = Harness(async, keys, tools: spy);
        final machine = h.phoneMachine;
        h.run(machine.connect());
        expect(
          machine.tools.enqueue(
            ToolData(id: 1, data: Uint8List(kMaxSealedBatchBytes), end: false),
          ),
          isFalse,
        );
        settle(async);
        expect(machine.state, isA<MachineReady>());
      });
    },
  );

  test('a lost channel: opens fail, streams hear it, nothing queued goes '
      'out; the new one asks for the list again', () {
    fakeAsync((async) {
      final spy = _Spy();
      final h = Harness(async, keys, tools: spy);
      final tools = h.phoneMachine.tools;
      h.run(tools.watch());
      settle(async);
      final listener = _Listener();
      tools.listen(5, listener);
      spy.say(const ToolAck([5, 10]));
      settle(async);
      expect(listener.heard, ['ack 10']);
      final opening = tools.open('k3f9za7q1m');
      Object? failure;
      opening.catchError((Object e) {
        failure = e;
        return const ToolOpened(rid: 0, ok: false);
      });
      tools.enqueue(const ToolEnd(id: 9, code: 'aborted'));
      final lists = spy.handled.whereType<ToolList>().length;
      h.disconnectPhone();
      settle(async);
      expect(listener.heard.last, 'lost');
      expect(failure, isA<MachineConnectionException>());
      h.reconnectPhone();
      settle(async, const Duration(seconds: 1));
      expect(spy.handled.whereType<ToolList>().length, lists + 1);
      expect(spy.handled.whereType<ToolEnd>().where((m) => m.id == 9), isEmpty);
    });
  });

  group('compatibility (E19, mandatory)', () {
    test('new phone, old desktop: no tools flag; a tool.* sent anyway is '
        'ignored, nothing waits forever, terminals fine', () {
      fakeAsync((async) {
        final h = Harness(async, keys); // an agent without tools for phones
        final machine = h.phoneMachine;
        h.run(machine.listSessions(includeDesktop: true));
        expect(machine.tools.supported, isFalse);
        expect(
          () => h.run(machine.tools.open('k3f9za7q1m')),
          throwsA(isA<MachineConnectionException>()),
        );
        final tab = h.run(machine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        h.pty.emit('still here\r\n');
        settle(async);
        expect(recorder.text, contains('still here'));
      });
    });

    test('old phone, new desktop: a phone that never asks gets no tool.*', () {
      fakeAsync((async) {
        final proxy = ToolProxy()..serve(_catalog());
        final toPhones = <OutboundMessage>[];
        proxy.outbound.listen(toPhones.add);
        final h = Harness(async, keys, tools: proxy);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        final recorder = TabRecorder(tab);
        proxy.serve(ToolCatalog([]));
        h.pty.emit('ok\r\n');
        settle(async, const Duration(seconds: 1));
        expect(toPhones, isEmpty);
        expect(recorder.text, contains('ok'));
        proxy.close();
      });
    });
  });

  // Beyond the brief's seven: what its prose asks for and they leave open.
  group('the page that holds the channel, the streams, unreadable bodies', () {
    test('a held page: a lost channel comes back with no terminal tab and '
        'asks for the list; links say so, credit starts again; a released '
        'page lets go (R4)', () {
      fakeAsync((async) {
        final spy = _Spy();
        final h = Harness(async, keys, tools: spy);
        final tools = h.phoneMachine.tools;
        final links = <bool>[];
        tools.links.listen(links.add);
        expect(tools.wantsChannel, isFalse);
        h.run(h.phoneMachine.connect());
        settle(async);
        final release = tools.hold();
        expect(tools.wantsChannel, isTrue);
        settle(async);
        expect(spy.handled.whereType<ToolList>(), hasLength(1));
        ToolSendWindow(tools.credit).onSent(1000);
        expect(tools.credit.inFlight, 1000);

        h.disconnectPhone();
        settle(async);
        expect(tools.connected, isFalse);
        expect(tools.credit.inFlight, 0);
        h.reconnectPhone();
        settle(async, const Duration(seconds: 1));
        expect(tools.connected, isTrue);
        expect(spy.handled.whereType<ToolList>(), hasLength(2));
        expect(links.first, isTrue);
        expect(links, contains(false));
        expect(links.last, isTrue);

        release();
        release(); // a second call changes nothing
        expect(tools.wantsChannel, isFalse);
        h.disconnectPhone();
        settle(async);
        h.reconnectPhone();
        settle(async, const Duration(seconds: 1));
        expect(tools.connected, isFalse);
      });
    });

    test('a stream hears its own id until the computer ends it or it is '
        'released; nothing else, and no ack of an ended stream', () {
      fakeAsync((async) {
        final spy = _Spy();
        final h = Harness(async, keys, tools: spy);
        final tools = h.phoneMachine.tools;
        h.run(h.phoneMachine.connect());
        settle(async);
        final a = _Listener();
        final b = _Listener();
        tools.listen(1, a);
        tools.listen(2, b);
        tools.acks.consumed(1, 10);
        spy.say(
          const ToolResponse(id: 1, status: 200, head: ['a', 'b'], end: false),
        );
        spy.say(ToolData(id: 1, data: Uint8List(3), end: false));
        spy.say(
          ToolWsMessage(id: 2, data: Uint8List(1), text: true, fin: true),
        );
        spy.say(const ToolAck([1, 5, 2, 6, 99, 1])); // 99 is nobody's
        spy.say(const ToolEnd(id: 1, code: 'gone'));
        spy.say(ToolData(id: 1, data: Uint8List(3), end: true)); // after it
        spy.say(const ToolEnd(id: 77, code: 'gone')); // nobody's
        settle(async);
        expect(a.heard, ['response', 'data', 'ack 5', 'end gone']);
        expect(b.heard, ['ws', 'ack 6']);

        tools.acks.consumed(2, 40);
        tools.release(2);
        spy.say(
          ToolWsMessage(id: 2, data: Uint8List(1), text: true, fin: true),
        );
        spy.say(const ToolAck([2, 9]));
        settle(async, const Duration(milliseconds: 200));
        expect(b.heard, ['ws', 'ack 6']);
        expect(spy.handled.whereType<ToolAck>(), isEmpty);
      });
    });

    test('a list or an opening that cannot be read leaves entries out and '
        'never throws (E19)', () {
      Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
      const good =
          '{"id":"a","name":"n","ws":"w","port":5173,"path":"/app?x=1",'
          '"group":"g"}';
      final listing = ToolListing.fromBody(
        bytes(
          '{"v":1,"tools":[$good,{"id":"b"},'
          '{"id":"c","name":"n","ws":"w","port":0,"path":"/","group":"g"},'
          '{"id":"c","name":"n","ws":"w","port":65536,"path":"/","group":"g"},'
          '{"id":"d","name":"n","ws":"w","port":80,"path":"http://x/",'
          '"group":"g"},'
          '{"id":"e","name":"n","ws":"w","port":80,"path":"//x/","group":"g"},'
          '{"id":"f","name":"n","ws":"w","port":"80","path":"/","group":"g"},'
          '{"id":"g","name":"n","ws":"w","port":80,"path":"/","group":7},'
          '7,null,"x"]}',
        ),
        available: true,
      );
      expect(listing.available, isTrue);
      expect(listing.tools.map((t) => t.id), ['a']);
      expect(listing.tools.single.path, '/app?x=1');
      for (final unreadable in [
        bytes('not json'),
        bytes('[1,2]'),
        bytes('{"tools":"x"}'),
        Uint8List.fromList([0xff, 0xfe]),
        Uint8List(0),
      ]) {
        final empty = ToolListing.fromBody(unreadable, available: false);
        expect(empty.tools, isEmpty);
        expect(empty.available, isFalse);
      }

      expect(ToolServing.fromBody(null), isEmpty);
      expect(ToolServing.fromBody(bytes('nope')), isEmpty);
      final serving = ToolServing.fromBody(
        bytes(
          '{"v":1,"tools":[{"id":"a","port":5173,"path":"/"},'
          '{"id":"b","port":70000,"path":"/"},'
          '{"id":"c","port":1,"path":"nope"},'
          '{"id":3,"port":1,"path":"/"},'
          '{"id":"d","port":1.5,"path":"/"},'
          '{"id":"e","port":1},5]}',
        ),
      );
      expect(serving.map((s) => s.id), ['a']);
    });
  });
}
