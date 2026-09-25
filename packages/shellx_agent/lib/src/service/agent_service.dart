import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pairing/pairing_code_manager.dart';
import '../session/session_manager.dart';
import '../trust/trusted_store.dart';
import 'agent_channel.dart';
import 'agent_events.dart';
import 'handshake_responder.dart';

/// The agent side of the relay protocol: answers handshakes, keeps at most
/// one encrypted channel per phone, routes app messages to [SessionManager]
/// and completes pairing.
///
/// [start] subscribes and calls `relay.start()`. [stop] drops every channel
/// and calls `relay.stop()`; it does not close sessions (call
/// `SessionManager.closeAll()` for that).
///
/// Frames, relay state changes, channel failures and [revoke] all run one
/// at a time through a single inbox, so trust decisions and the channel
/// table never interleave. Only [stop] acts immediately; work it interrupts
/// re-checks the channel table after every await.
///
/// A phone paired here stays "unregistered" (persisted in [TrustedStore])
/// until the relay acknowledges its `POST /v1/pairings`. Until then a
/// `pairing_removed` for it is ignored: the relay replays the tombstone of
/// an earlier unpair on every connect until that POST clears it. The POST
/// is retried after every relay connect and, while connected, with backoff.
final class AgentService {
  AgentService({
    required RelayConnection relay,
    required ShellxApi api,
    required String deviceId,
    required NoiseKeyPair identity,
    required TrustedStore trusted,
    required SessionManager sessions,
    required PairingCodeManager pairing,
    required String appVersion,
    Duration flushInterval = const Duration(milliseconds: 16),
  }) : _relay = relay,
       _api = api,
       _deviceId = deviceId,
       _identity = identity,
       _trusted = trusted,
       _sessions = sessions,
       _pairing = pairing,
       _flushInterval = flushInterval,
       _responder = HandshakeResponder(
         deviceId: deviceId,
         identity: identity,
         appVersion: appVersion,
         trusted: trusted,
         pairing: pairing,
       );

  final RelayConnection _relay;
  final ShellxApi _api;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final TrustedStore _trusted;
  final SessionManager _sessions;
  final PairingCodeManager _pairing;
  final Duration _flushInterval;
  final HandshakeResponder _responder;

  final _events = StreamController<AgentEvent>.broadcast();
  final _channels = <String, AgentChannel>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _inbox = Future.value();
  bool _running = false;

  /// Bumped by [start] and [stop]: inbox work queued under an older value
  /// is skipped, and an HS1 answered across a stop installs no channel.
  int _epoch = 0;

  final _registrationBackoff = Backoff();
  Timer? _registrationTimer;
  bool _registering = false;
  bool _registerAgain = false;

  Stream<AgentEvent> get events => _events.stream;

  int get activeChannelCount => _channels.length;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _epoch++;
    _subscriptions
      ..add(_relay.frames.listen((frame) => _enqueue(() => _onFrame(frame))))
      ..add(
        _relay.states.listen(
          (state) => _enqueue(() async {
            if (state == RelayConnectionState.connected) {
              _registrationBackoff.reset();
              _registerSoon();
              return;
            }
            _registrationTimer?.cancel();
            _registrationTimer = null;
            _dropAllChannels();
            if (state == RelayConnectionState.revoked) {
              _events.add(const AgentRevoked());
            }
          }),
        ),
      )
      ..add(
        _sessions.outbound.listen(
          (out) => _channels[out.mobileId]?.enqueue(out.message),
        ),
      )
      ..add(
        _sessions.opened.listen(
          (event) => _events.add(
            SessionOpenedByMobile(
              mobileName: _channels[event.mobileId]?.name ?? event.mobileId,
              sessionId: event.sessionId,
            ),
          ),
        ),
      );
    _relay.start();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _epoch++;
    _registrationTimer?.cancel();
    _registrationTimer = null;
    for (final subscription in _subscriptions) {
      // Not awaited: cancel() may return a root-zone future.
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _dropAllChannels();
    await _relay.stop();
  }

  /// Creates a single-use pairing code and the QR URI that carries it.
  PairingUri startPairing() {
    final offer = _pairing.create();
    return PairingUri(
      agentDeviceId: _deviceId,
      agentPublicKey: _identity.publicKey,
      secret: offer.secret,
    );
  }

  /// The QR window was closed: the code stops working immediately.
  void cancelPairing() => _pairing.invalidate();

  /// Tray → "Paired devices" → Revoke (spec §5.5). Works whether or not the
  /// service is running. The local part runs through the inbox, after any
  /// HS1 already being answered, so no channel for [mobileId] survives it;
  /// the display-only server record is deleted afterwards, outside the
  /// inbox, so a slow request never stalls frame handling.
  ///
  /// Removes trust and any unregistered mark, and kills the sessions
  /// attached to that phone (spec §5.5: "phiên đang gắn với điện thoại
  /// đó"). Unattached sessions belong to no phone, and the revoked phone can
  /// no longer attach, so they keep running until closed from the tray.
  Future<void> revoke(String mobileId) async {
    await _serialize(() async {
      await _trusted.remove(mobileId);
      _sessions.closeSessionsAttachedTo(mobileId);
      _dropChannel(mobileId);
    });
    try {
      await _api.deletePairing(_deviceId, mobileId);
    } on ApiException {
      // The server record is display-only; local trust is already gone.
    }
  }

  /// Runs [task] after every task queued before it. The returned future
  /// carries [task]'s outcome; the inbox itself never stops on an error.
  Future<T> _serialize<T>(Future<T> Function() task) {
    final result = _inbox.then((_) => task());
    _inbox = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Queues [task] unless [start]/[stop] runs before its turn. Errors are
  /// dropped: a failed frame must not break the ones after it.
  void _enqueue(Future<void> Function() task) {
    final epoch = _epoch;
    _serialize(() async {
      if (epoch == _epoch) await task();
    }).ignore();
  }

  Future<void> _onFrame(RelayFrame frame) async {
    switch (frame) {
      case DataFrame():
        await _onData(frame);
      case PresenceFrame(:final deviceId, :final online):
        if (!online) _dropChannel(deviceId);
      case ErrorFrame(:final code, :final deviceId, :final channel):
        if (code == RelayErrorCode.peerOffline &&
            _channels[deviceId]?.channelId == channel) {
          _dropChannel(deviceId);
        }
      case EventFrame(:final event):
        await _onEvent(event);
    }
  }

  Future<void> _onData(DataFrame frame) async {
    final ChannelPayload payload;
    try {
      payload = ChannelPayload.decode(frame.payload);
    } on FrameFormatException {
      return;
    }
    switch (payload.kind) {
      case PayloadKind.hs1Ik || PayloadKind.hs1IkPsk2:
        await _onHello(frame, payload);
      case PayloadKind.transport:
        await _onTransport(frame, payload.noiseMessage);
      case PayloadKind.hs2:
        break; // The agent is always the responder.
    }
  }

  Future<void> _onHello(DataFrame frame, ChannelPayload payload) async {
    final epoch = _epoch;
    final mobileId = frame.peer;
    HandshakeAnswer? answer;
    try {
      answer = await _responder.answer(
        mobileId: mobileId,
        kind: payload.kind,
        message: payload.noiseMessage,
      );
    } catch (_) {
      // For example the trust list could not be read: fail closed, silently.
      answer = null;
    }
    if (answer == null || epoch != _epoch) return;
    _relay.send(
      DataFrame(peer: mobileId, channel: frame.channel, payload: answer.reply),
    );
    final transport = answer.transport;
    if (transport == null) return; // Status was not ok: no channel.
    // One channel per phone: a new accepted HS1 replaces the old channel.
    final previous = _channels.remove(mobileId);
    if (previous != null) {
      previous.close();
      _sessions.mobileDisconnected(mobileId);
    }
    late final AgentChannel channel;
    channel = AgentChannel(
      mobileId: mobileId,
      channelId: frame.channel,
      name: answer.hello.name,
      remoteStatic: answer.remoteStatic,
      secure: SecureChannel(transport),
      send: _relay.send,
      pairingSecret: answer.pairingSecret,
      // A batch that could not be sealed or sent leaves a gap in the
      // stream: drop the channel like a decrypt error. The phone
      // re-handshakes and re-attaches from last_seq.
      onFailure: () => _enqueue(() async => _dropChannel(mobileId, channel)),
      flushInterval: _flushInterval,
    );
    _channels[mobileId] = channel;
    _events.add(ActiveChannelsChanged(_channels.length));
  }

  Future<void> _onTransport(DataFrame frame, Uint8List noiseMessage) async {
    final mobileId = frame.peer;
    final channel = _channels[mobileId];
    if (channel == null || channel.channelId != frame.channel) return;
    final List<AppMessage> messages;
    try {
      messages = await channel.open(noiseMessage);
    } catch (_) {
      // Any decrypt/decode error kills the channel.
      _dropChannel(mobileId, channel);
      return;
    }
    if (!identical(_channels[mobileId], channel)) return;
    if (channel.isPairing) {
      // A pairing channel carries exactly one payload, whatever it holds.
      _dropChannel(mobileId, channel);
      if (messages.firstOrNull is PairConfirm) await _completePairing(channel);
      return;
    }
    for (final message in messages) {
      if (message is PairConfirm) continue;
      await _sessions.handle(mobileId, message);
      if (!identical(_channels[mobileId], channel)) {
        // stop() dropped the channel meanwhile: undo any attach the
        // message made, so no session stays attached to a missing channel.
        _sessions.mobileDisconnected(mobileId);
        return;
      }
    }
  }

  /// Pairing succeeds only on a decrypted `pair.confirm` while the code used
  /// for the handshake is still the active one (spec §5.3 step 5). An ok
  /// IKpsk2 answer only meant a code was active at HS1: the PSK is mixed
  /// into message 2, so this message is the first proof the phone has it.
  Future<void> _completePairing(AgentChannel channel) async {
    final active = _pairing.activeSecret;
    if (active == null || !constantTimeEquals(active, channel.pairingSecret!)) {
      return;
    }
    _pairing.invalidate();
    final device = TrustedDevice(
      mobileId: channel.mobileId,
      publicKey: channel.remoteStatic,
      name: channel.name,
      pairedAt: DateTime.now().toUtc(),
    );
    // Unregistered until the relay acknowledges POST /v1/pairings, so a
    // replayed tombstone of an earlier unpair cannot undo this trust.
    await _trusted.add(device, unregistered: true);
    _events.add(MobilePaired(device));
    _registerSoon();
  }

  /// Idempotent: the relay replays `pairing_removed` on every connect, so a
  /// phone that is already untrusted (and has no channel) is left as is
  /// (and [TrustedStore.remove] writes nothing). Ignored for an unregistered
  /// phone: it may be the tombstone of an unpair from before this pairing.
  Future<void> _onEvent(Map<String, String> event) async {
    if (event['event'] != 'pairing_removed' || event['agent_id'] != _deviceId) {
      return;
    }
    final mobileId = event['mobile_id'];
    if (mobileId == null) return;
    if ((await _trusted.unregistered()).contains(mobileId)) return;
    await _trusted.remove(mobileId);
    _dropChannel(mobileId);
  }

  bool get _connected =>
      _running && _relay.state == RelayConnectionState.connected;

  void _registerSoon() => unawaited(_registerPairings());

  /// `POST /v1/pairings` for every unregistered phone, while connected.
  /// HTTP runs outside the inbox (a slow request must not stall frames);
  /// the bookkeeping runs inside it, after any frame already received — the
  /// relay sends its tombstones right after the upgrade, before any POST
  /// response can arrive. Never throws.
  Future<void> _registerPairings() async {
    if (_registering) {
      _registerAgain = true;
      return;
    }
    _registering = true;
    _registrationTimer?.cancel();
    _registrationTimer = null;
    var pass = _Pass.done;
    try {
      do {
        _registerAgain = false;
        pass = await _registerOnce();
      } while (_registerAgain && pass == _Pass.done);
    } catch (_) {
      pass = _Pass.retry; // For example the trust store could not be read.
    } finally {
      _registering = false;
    }
    if (!_connected) return; // The next connect retries.
    switch (pass) {
      case _Pass.done:
        _registrationBackoff.reset();
      case _Pass.retry:
        _registrationTimer = Timer(_registrationBackoff.next(), _registerSoon);
      case _Pass.unauthorized:
        break; // AgentRevoked takes over; the next connect retries.
    }
  }

  Future<_Pass> _registerOnce() async {
    var pass = _Pass.done;
    for (final mobileId in await _trusted.unregistered()) {
      if (!_connected) return _Pass.retry;
      try {
        await _api.createPairing(mobileId);
      } on ApiException catch (error) {
        final status = error.status;
        if (status == 401) return _Pass.unauthorized;
        if (status >= 400 && status < 500 && status != 429) {
          // The relay refused the pairing record: stop asking. Local trust
          // stays as it is.
          await _serialize(() => _trusted.markRegistered(mobileId));
          continue;
        }
        pass = _Pass.retry; // Network (0), 429 or 5xx.
        continue;
      }
      final wasUnregistered = await _serialize(
        () => _trusted.markRegistered(mobileId),
      );
      if (!wasUnregistered) {
        // Revoked while the POST was in flight: take the record back.
        unawaited(_deletePairingQuietly(mobileId));
      }
    }
    return pass;
  }

  Future<void> _deletePairingQuietly(String mobileId) async {
    try {
      await _api.deletePairing(_deviceId, mobileId);
    } catch (_) {
      // Display-only record; nothing else to do.
    }
  }

  /// Drops [mobileId]'s channel; when [only] is given, only if that exact
  /// channel is still the current one.
  void _dropChannel(String mobileId, [AgentChannel? only]) {
    final channel = _channels[mobileId];
    if (channel == null || (only != null && !identical(channel, only))) {
      return;
    }
    _channels.remove(mobileId);
    channel.close();
    _sessions.mobileDisconnected(mobileId);
    _events.add(ActiveChannelsChanged(_channels.length));
  }

  void _dropAllChannels() {
    for (final mobileId in _channels.keys.toList()) {
      _dropChannel(mobileId);
    }
  }
}

/// Outcome of one pass over the unregistered phones.
enum _Pass { done, retry, unauthorized }
