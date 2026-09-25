// Compile-time check that the public API matches the overview contract
// (docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md §5.1–§5.5).
// Every assignment below fails to compile if a name or type drifts.
// ignore_for_file: unused_local_variable, omit_local_variable_types, prefer_function_declarations_over_variables
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

void main() {
  test('§5.1 utilities and relay frames', () {
    const String nil = nilUuid;
    Uint8List Function(String) toBytes = uuidToBytes;
    String Function(Uint8List) fromBytes = uuidFromBytes;
    String Function(Uint8List) b64 = base64UrlNoPad;
    Uint8List Function(String) unb64 = fromBase64UrlNoPad;
    bool Function(Uint8List, Uint8List) eq = constantTimeEquals;

    final ChannelId id = ChannelId(Uint8List(8));
    final ChannelId random = ChannelId.random(Random(1));
    final ChannelId zero = ChannelId.zero;
    final Uint8List idBytes = id.bytes;

    const int version = kRelayProtocolVersion;
    const int maxFrame = kMaxFrameBytes;
    const List<int> codes = [
      RelayCloseCode.replaced,
      RelayCloseCode.revoked,
      RelayCloseCode.rateLimited,
    ];
    final int wire = RelayErrorCode.peerOffline.wire;
    RelayErrorCode Function(int) fromWire = RelayErrorCode.fromWire;
    const FrameFormatException formatError = FrameFormatException('x');
    final String message = formatError.message;

    RelayFrame Function(Uint8List) decode = RelayFrame.decode;
    final DataFrame data = DataFrame(
      peer: nilUuid,
      channel: zero,
      payload: Uint8List(0),
    );
    final String peer = data.peer;
    final ChannelId channel = data.channel;
    final Uint8List payload = data.payload;
    const PresenceFrame presence = PresenceFrame(
      deviceId: nilUuid,
      online: true,
    );
    final ErrorFrame error = ErrorFrame(code: RelayErrorCode.badFrame);
    final String errorDevice = error.deviceId;
    final ChannelId errorChannel = error.channel;
    const EventFrame event = EventFrame({'event': 'pairing_removed'});
    final Map<String, String> eventMap = event.event;
    final Uint8List encoded = data.encode();
    expect(RelayErrorCode.values.map((c) => c.wire), [1, 2, 3, 4]);
  });

  test('§5.2 Noise', () async {
    final NoiseKeyPair keys = await NoiseKeyPair.generate();
    final NoiseKeyPair same = await NoiseKeyPair.fromPrivateKey(
      keys.privateKey,
    );
    final NoiseKeyPair manual = NoiseKeyPair(
      privateKey: keys.privateKey,
      publicKey: keys.publicKey,
    );
    expect(NoisePattern.values, [NoisePattern.ik, NoisePattern.ikPsk2]);
    const NoiseException noiseError = NoiseException('x');
    final initiator = NoiseHandshake.initiator(
      pattern: NoisePattern.ik,
      localStatic: keys,
      remoteStatic: keys.publicKey,
      prologue: Uint8List(0),
      psk: null,
      ephemeral: null,
    );
    final responder = NoiseHandshake.responder(
      pattern: NoisePattern.ik,
      localStatic: keys,
      prologue: Uint8List(0),
      psk: null,
      ephemeral: null,
    );
    Future<Uint8List> Function([Uint8List?]) write = initiator.writeMessage;
    Future<Uint8List> Function(Uint8List) read = responder.readMessage;
    final bool complete = initiator.isComplete;
    final Uint8List? remote = responder.remoteStatic;
    final Uint8List hash = initiator.handshakeHash;
    NoiseTransport Function() split = initiator.split;
    await responder.readMessage(await initiator.writeMessage());
    await initiator.readMessage(await responder.writeMessage());
    final NoiseTransport transport = initiator.split();
    Future<Uint8List> Function(Uint8List) encrypt = transport.encrypt;
    Future<Uint8List> Function(Uint8List) decrypt = transport.decrypt;
  });

  test('§5.3 channel payload, secure channel, pairing uri', () {
    expect(PayloadKind.values.map((k) => k.wire), [1, 2, 3, 4]);
    final ChannelPayload payload = ChannelPayload(
      PayloadKind.transport,
      Uint8List(0),
    );
    final PayloadKind kind = payload.kind;
    final Uint8List noise = payload.noiseMessage;
    final Uint8List bytes = payload.encode();
    ChannelPayload Function(Uint8List) decode = ChannelPayload.decode;
    Uint8List Function({
      required String agentDeviceId,
      required String mobileDeviceId,
    })
    prologue = buildPrologue;
    const int chunk = kMaxOutputChunk;
    expect(chunk, 16 * 1024);
    SecureChannel Function(NoiseTransport) make = SecureChannel.new;
    Future<Uint8List> Function(List<AppMessage>) Function(SecureChannel) seal =
        (c) => c.seal;
    Future<List<AppMessage>> Function(Uint8List) Function(SecureChannel) open =
        (c) => c.open;

    final PairingUri uri = PairingUri(
      agentDeviceId: nilUuid,
      agentPublicKey: Uint8List(32),
      secret: Uint8List(32),
    );
    final String agent = uri.agentDeviceId;
    final Uint8List key = uri.agentPublicKey;
    final Uint8List secret = uri.secret;
    final String text = uri.toUriString();
    PairingUri Function(String) parse = PairingUri.parse;
  });

  test('§5.4 messages', () {
    const int proto = kAppProtocolVersion;
    expect(DevicePlatform.values.map((p) => p.name), [
      'macos',
      'windows',
      'ios',
      'android',
    ]);
    expect(DeviceKind.values.map((k) => k.name), ['agent', 'mobile']);
    final String statusWire = HandshakeStatus.pairingInvalid.wire;
    expect(HandshakeStatus.values.map((s) => s.wire), [
      'ok',
      'untrusted',
      'pairing_invalid',
      'proto_unsupported',
    ]);
    final Hs1Payload hs1 = Hs1Payload(
      proto: 1,
      app: '1.0.0',
      name: 'n',
      platform: DevicePlatform.ios,
    );
    Hs1Payload Function(Uint8List) hs1Decode = Hs1Payload.decode;
    final Hs2Payload hs2 = Hs2Payload(
      proto: 1,
      app: '1.0.0',
      status: HandshakeStatus.ok,
    );
    Hs2Payload Function(Uint8List) hs2Decode = Hs2Payload.decode;
    final Uint8List hs1Bytes = hs1.encode();
    final Uint8List hs2Bytes = hs2.encode();

    AppMessage? Function(Map<Object?, Object?>) fromMap = AppMessage.fromMap;
    final List<AppMessage> all = [
      const PairConfirm(),
      const SessionList(),
      const SessionListResult([
        SessionInfo(id: 1, index: 1, shell: 's', createdAt: 0, attached: true),
      ]),
      const SessionOpen(cols: 1, rows: 1),
      const SessionOpened(id: 1, index: 1, shell: 's'),
      const SessionAttach(id: 1, cols: 1, rows: 1, lastSeq: 0),
      const SessionAttached(id: 1),
      const SessionReset(id: 1),
      OutputMessage(id: 1, seq: 0, data: Uint8List(0)),
      const AckMessage(id: 1, seq: 0),
      InputMessage(id: 1, data: Uint8List(0)),
      const ResizeMessage(id: 1, cols: 1, rows: 1),
      const SessionClose(id: 1),
      const SessionExited(id: 1, exitCode: 0),
      const SessionDetached(id: 1, reason: DetachReason.takenOver),
      const ErrorMessage(code: AppErrorCode.spawnFailed, message: 'm', id: 1),
    ];
    final String type = all.first.type;
    final Map<String, Object?> map = all.first.toMap();
    final int? errorId = const ErrorMessage(
      code: AppErrorCode.sessionLimit,
      message: 'm',
    ).id;
    final String reasonWire = DetachReason.closedByHost.wire;
    final String codeWire = AppErrorCode.sessionNotFound.wire;
    Uint8List Function(List<AppMessage>) enc = encodeBatch;
    List<AppMessage> Function(Uint8List) dec = decodeBatch;
    expect(decodeBatch(encodeBatch(all)), all);
  });

  test('§5.5 storage, identity, REST, relay connection', () {
    final KeyValueStore store = InMemoryKeyValueStore();
    Future<String?> Function(String) read = store.read;
    Future<void> Function(String, String) write = store.write;
    Future<void> Function(String) delete = store.delete;
    const String storageKey = DeviceIdentity.storageKey;
    Future<NoiseKeyPair> Function(KeyValueStore) load =
        DeviceIdentity.loadOrCreate;

    final DeviceInfo device = DeviceInfo(
      kind: DeviceKind.mobile,
      name: 'n',
      platform: DevicePlatform.android,
      publicKey: Uint8List(32),
    );
    final Map<String, Object?> json = device.toJson();
    const AuthResult auth = AuthResult(userId: 'u', deviceId: 'd', token: 't');
    final RemoteDevice remote = RemoteDevice(
      id: 'i',
      kind: DeviceKind.agent,
      name: 'n',
      platform: DevicePlatform.macos,
      online: true,
      lastSeenAt: DateTime.utc(2026),
      pairedWithMe: false,
    );
    final DateTime? lastSeen = remote.lastSeenAt;
    final VersionInfo info = VersionInfo(
      minAgent: '1.0.0',
      minMobile: '1.0.0',
      latestAgent: LatestAgent(
        version: '1.0.0',
        macUrl: Uri.parse('https://x'),
        winUrl: Uri.parse('https://y'),
      ),
    );
    final Uri mac = info.latestAgent.macUrl;
    const ApiException apiError = ApiException(
      status: 0,
      code: 'network',
      message: 'm',
    );
    final ShellxApi api = ShellxApi(
      baseUri: Uri.parse('https://relay.shellx.pro'),
      httpClient: http.Client(),
    );
    api.token = 'x';
    final String? token = api.token;
    Future<AuthResult> Function(String, String, DeviceInfo) register =
        api.register;
    Future<AuthResult> Function(String, String, DeviceInfo) login = api.login;
    Future<void> Function() logout = api.logout;
    Future<void> Function(String) change = api.changePassword;
    Future<void> Function(String) deleteAccount = api.deleteAccount;
    Future<List<RemoteDevice>> Function() devices = api.devices;
    Future<void> Function(String) create = api.createPairing;
    Future<void> Function(String, String) remove = api.deletePairing;
    Future<VersionInfo> Function() version = api.version;
    void Function() apiClose = api.close;
    int Function(String, String) compare = compareVersions;

    Stream<Object> Function(RelaySocket) messages = (s) => s.messages;
    void Function(String) Function(RelaySocket) sendText = (s) => s.sendText;
    void Function(Uint8List) Function(RelaySocket) sendBytes = (s) =>
        s.sendBytes;
    Future<void> Function([int?, String?]) Function(RelaySocket) close = (s) =>
        s.close;
    int? Function(RelaySocket) closeCode = (s) => s.closeCode;
    RelaySocketConnector connector = ioRelaySocketConnector;
    final Backoff backoff = Backoff(
      initial: const Duration(seconds: 1),
      max: const Duration(seconds: 30),
      random: Random(1),
    );
    Duration Function() next = backoff.next;
    void Function() reset = backoff.reset;
    expect(RelayConnectionState.values.map((s) => s.name), [
      'disconnected',
      'connecting',
      'connected',
      'revoked',
      'replaced',
      'stopped',
    ]);
    final RelayConnection relay = RelayConnection(
      wsUri: Uri.parse('wss://relay.shellx.pro/v1/ws'),
      token: () => null,
      connector: ioRelaySocketConnector,
      backoff: backoff,
      pingInterval: const Duration(seconds: 30),
      pongTimeout: const Duration(seconds: 10),
    );
    final RelayConnectionState state = relay.state;
    final Stream<RelayConnectionState> states = relay.states;
    final Stream<RelayFrame> frames = relay.frames;
    void Function() start = relay.start;
    Future<void> Function() stop = relay.stop;
    bool Function(RelayFrame) send = relay.send;
    void Function() now = relay.reconnectNow;
  });
}
