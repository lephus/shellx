import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pairing/pairing_code_manager.dart';
import '../pairing/pairing_id.dart';
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
/// Every pairing has a pairing id (UUIDv7 from `clock`, generated at
/// `pair.confirm`, stored in the trust entry). `pairing_removed`, the
/// relay's `410` and the agent's own revoke all act on one pairing id, so a
/// tombstone of an older pairing of the same phone (replayed on every
/// connect until a newer `POST /v1/pairings` lands) never undoes a newer
/// one. A new pairing stays marked unregistered in [TrustedStore] until the
/// relay acknowledges its POST, which is retried after every relay connect
/// and, while connected, with `registrationBackoff` — only for the phone's
/// current pairing id.
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
    DateTime Function()? clock,
    Backoff? registrationBackoff,
  }) : _relay = relay,
       _clock = clock ?? DateTime.now,
       _pairingIds = PairingIdGenerator(now: clock),
       _registrationBackoff = registrationBackoff ?? Backoff(),
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

  /// Waits before the second and third attempt of a pairing record's
  /// DELETE (the same as the phone's unpair).
  static const _deleteRetryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
  ];

  final RelayConnection _relay;
  final DateTime Function() _clock;
  final PairingIdGenerator _pairingIds;
  final Backoff _registrationBackoff;
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
  /// Removes the trust entry (and its unregistered mark), and kills the
  /// sessions attached to that phone (spec §5.5: "phiên đang gắn với điện
  /// thoại đó"). Unattached sessions belong to no phone, and the revoked
  /// phone can no longer attach, so they keep running until closed from the
  /// tray. The DELETE carries the entry's pairing id, so a revoke that lands
  /// after a quick re-pair never removes the newer pairing.
  Future<void> revoke(String mobileId) async {
    final removed = await _serialize(() async {
      final device = await _trusted.find(mobileId);
      if (device != null) {
        await _trusted.remove(mobileId, pairingId: device.pairingId);
      }
      _sessions.closeSessionsAttachedTo(mobileId);
      _dropChannel(mobileId);
      return device;
    });
    if (removed != null) await _deletePairing(mobileId, removed.pairingId);
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
    final sent = _relay.send(
      DataFrame(peer: mobileId, channel: frame.channel, payload: answer.reply),
    );
    final transport = answer.transport;
    // Status not ok: no channel. HS2 not sent: the phone cannot use a new
    // channel, so the existing one (if any) stays.
    if (transport == null || !sent) return;
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
      try {
        await _sessions.handle(mobileId, message);
      } catch (_) {
        // For example a PTY write that throws: only this message is lost,
        // not the rest of the batch (the channel itself is fine).
      }
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
      pairedAt: _clock().toUtc(),
      pairingId: _pairingIds.next(),
    );
    // Unregistered until the relay acknowledges POST /v1/pairings.
    await _trusted.add(device, unregistered: true);
    _events.add(MobilePaired(device));
    _registerSoon();
  }

  /// Removes trust only when the event names the pairing the phone is
  /// trusted under: a tombstone of an older pairing (replayed on every
  /// connect until a newer POST lands) or a duplicate changes nothing and
  /// writes nothing.
  Future<void> _onEvent(Map<String, String> event) async {
    if (event['event'] != 'pairing_removed' || event['agent_id'] != _deviceId) {
      return;
    }
    final mobileId = event['mobile_id'];
    final pairingId = event['pairing_id'];
    if (mobileId == null || pairingId == null) return;
    await _pairingRemoved(mobileId, pairingId);
  }

  /// The phone unpaired pairing [pairingId] (EVENT or `410`): if it is still
  /// the phone's trusted pairing, trust and the channel go.
  Future<void> _pairingRemoved(String mobileId, String pairingId) async {
    if (await _trusted.remove(mobileId, pairingId: pairingId)) {
      _dropChannel(mobileId);
    }
  }

  bool get _connected =>
      _running && _relay.state == RelayConnectionState.connected;

  void _registerSoon() => unawaited(_registerPairings());

  /// `POST /v1/pairings` for every unregistered pairing, while connected.
  /// HTTP runs outside the inbox (a slow request must not stall frames);
  /// the bookkeeping runs inside it and acts only on the same pairing id.
  /// Never throws.
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
    for (final device in await _trusted.unregistered()) {
      if (!_connected) return _Pass.retry;
      final mobileId = device.mobileId;
      final pairingId = device.pairingId;
      // Only the phone's current pairing is ever (re)sent: an earlier POST
      // of this pass may have taken long enough for a re-pair or revoke.
      if ((await _trusted.find(mobileId))?.pairingId != pairingId) continue;
      try {
        await _api.createPairing(mobileId, pairingId: pairingId);
      } on ApiException catch (error) {
        final status = error.status;
        if (status == 401) return _Pass.unauthorized;
        if (status == 410) {
          // The phone already unpaired this pairing (or the id is refused).
          await _serialize(() => _pairingRemoved(mobileId, pairingId));
        } else if (status >= 400 && status < 500 && status != 429) {
          // The relay refused the record for good: stop asking. Local
          // trust stays as it is.
          await _serialize(() => _trusted.markRegistered(mobileId, pairingId));
        } else {
          pass = _Pass.retry; // Network (0), 429 or 5xx: same id again.
        }
        continue;
      }
      final current = await _serialize(
        () => _trusted.markRegistered(mobileId, pairingId),
      );
      if (!current) {
        // Revoked or re-paired while the POST was in flight: take this
        // pairing's record back (a newer pairing's record is untouched).
        unawaited(_deletePairing(mobileId, pairingId));
      }
    }
    return pass;
  }

  /// `DELETE /v1/pairings` for pairing [pairingId] only. A network error or
  /// a 5xx is retried (3 attempts in all, as the phone's unpair); anything
  /// else, and the last failure, is ignored: the record is display-only and
  /// trust is already gone. Never throws.
  Future<void> _deletePairing(String mobileId, String pairingId) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _api.deletePairing(_deviceId, mobileId, pairingId: pairingId);
        return;
      } on ApiException catch (error) {
        final retry = error.status == 0 || error.status >= 500;
        if (!retry || attempt == _deleteRetryDelays.length) return;
      } catch (_) {
        return;
      }
      await Future<void>.delayed(_deleteRetryDelays[attempt]);
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
