import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

const pipePhone = 'b0000000-0000-4000-8000-000000000002';

/// Polls [condition] every 10 ms until it holds (fails after [timeout]).
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

AppMessage _wire(AppMessage m) => decodeBatch(encodeBatch([m])).single;

/// A phone's [MachineTools] and a desktop's [ToolProxy] joined in memory, as
/// an established channel would: every message crosses the wire's encoding,
/// delivery is in a microtask, the batches the phone sends are counted.
final class ToolPipe {
  ToolPipe(this.proxy) {
    tools = MachineTools(
      send: _toDesktop,
      connect: () async {
        if (!connected) {
          throw const MachineConnectionException(
            MachineConnectionFailure.agentOffline,
          );
        }
      },
      timeout: const Duration(seconds: 5),
    );
    proxy.outbound
        .where((o) => o.mobileId == pipePhone)
        .listen(
          (o) => scheduleMicrotask(() {
            if (connected) tools.handle(_wire(o.message) as ToolMessage);
          }),
        );
    tools.channelReady();
  }

  final ToolProxy proxy;
  late final MachineTools tools;
  bool connected = true;

  /// When each batch (one relay frame) left the phone.
  final batches = <Duration>[];
  final _clock = Stopwatch()..start();

  bool _toDesktop(List<AppMessage> batch) {
    if (!connected) return false;
    batches.add(_clock.elapsed);
    final messages = decodeBatch(encodeBatch(batch));
    scheduleMicrotask(() {
      for (final m in messages) {
        if (connected) proxy.handle(pipePhone, m as ToolMessage);
      }
    });
    return true;
  }

  /// The channel drops (relay gone, app in the background).
  void drop() {
    connected = false;
    tools.channelLost();
    proxy.phoneGone(pipePhone);
  }

  /// A new channel.
  void restore() {
    connected = true;
    tools.channelReady();
  }
}

/// Reaches [::1] only: the desktop's side of a test where the phone's server
/// holds 127.0.0.1 on the same port (one machine plays both).
Future<Socket> ipv6Only(int port) =>
    Socket.connect(InternetAddress.loopbackIPv6, port);

/// One answer the [Webview] got.
final class Page {
  Page(this.status, this.headers, this.body);
  final int status;
  final Map<String, List<String>> headers;
  final Uint8List body;
  String get text => String.fromCharCodes(body);
}

/// The phone's webview, as far as the server can tell: it always reaches
/// 127.0.0.1 (this phone's loopback), sends the `Host` of the URL, keeps the
/// cookies it is given (by name; HttpOnly ones too) and follows nothing.
final class Webview {
  final _client = HttpClient()
    ..findProxy = ((_) => 'DIRECT')
    ..autoUncompress = false
    ..connectionFactory = (uri, _, _) async => ConnectionTask.fromSocket(
      Socket.connect(InternetAddress.loopbackIPv4, uri.port),
      () {},
    );
  final cookies = <String, String>{};

  String get cookieHeader =>
      [for (final e in cookies.entries) '${e.key}=${e.value}'].join('; ');

  Future<Page> request(
    Uri url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    List<int>? body,
    bool withCookies = true,
  }) async {
    final request = await _client.openUrl(method, url);
    request.followRedirects = false;
    if (withCookies && cookies.isNotEmpty) {
      request.headers.set('cookie', cookieHeader);
    }
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    final response = await request.close();
    final got = <String, List<String>>{};
    response.headers.forEach((name, values) => got[name] = values);
    for (final cookie in got['set-cookie'] ?? const <String>[]) {
      final pair = cookie.split(';').first;
      final at = pair.indexOf('=');
      cookies[pair.substring(0, at)] = pair.substring(at + 1);
    }
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return Page(response.statusCode, got, Uint8List.fromList(bytes));
  }

  /// Loads the entry URL, then where it sends the webview.
  Future<Page> enter(Uri entry) async {
    final first = await request(entry);
    final location = first.headers['location']?.single;
    if (first.status != 303 || location == null) return first;
    return request(entry.resolve(location));
  }

  Future<WebSocket> socket(
    Uri url, {
    List<String>? protocols,
    String? origin,
  }) => WebSocket.connect(
    url.toString(),
    protocols: protocols,
    headers: {
      if (cookies.isNotEmpty) 'cookie': cookieHeader,
      'origin': ?origin,
    },
    customClient: _client,
  );

  void close() => _client.close(force: true);
}
