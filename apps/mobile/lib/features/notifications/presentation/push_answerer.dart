import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/notifications/domain/push_answer.dart';
import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';
import 'package:shellx_mobile/features/notifications/presentation/notification_opener.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// How a push's answer ended, for the toast that says it.
enum _Tone { done, note, problem }

/// V2-2b B10: a tap on "Cho phép" / "Từ chối" of an AI permission push. The app has come to the front (both buttons
/// open it); the answer goes only once the app's own lock is open (R7), and it goes once: one `ai.answer` on the
/// ordinary channel, its `ai.result` awaited, never sent again after a lost channel (V2-2 D13), never twice for the
/// same request. Then the session opens (through [NotificationOpener], which also finds a session again after the
/// computer restarted, B23) and a toast says how it ended: "Đã cho phép: Sửa src/main.ts", "Yêu cầu này đã được trả
/// lời ở nơi khác."… Nothing here is ever logged but error types.
@lazySingleton
class PushAnswerer {
  PushAnswerer({
    required SessionHolder session,
    required AppLockController lock,
    required NotificationOpener opener,
    required PopupHandler Function() popup,
    S Function()? words,
    this.patience = const Duration(minutes: 2),
    this.relayWait = const Duration(seconds: 10),
  }) : _session = session,
       _lock = lock,
       _opener = opener,
       _popup = popup,
       _words = words ?? (() => S.current);

  @factoryMethod
  static PushAnswerer create(SessionHolder session, AppLockController lock, NotificationOpener opener) => PushAnswerer(
    session: session,
    lock: lock,
    opener: opener,
    // Resolved when a toast shows: the popup handler needs the router's context.
    popup: () => getIt<PopupHandler>(),
  );

  final SessionHolder _session;
  final AppLockController _lock;
  final NotificationOpener _opener;
  final PopupHandler Function() _popup;
  final S Function() _words;

  /// How long an answer waits for the app's lock to open before it is dropped (R7).
  final Duration patience;

  /// How long it waits for the relay at a launch from the push, before saying the computer did not answer.
  final Duration relayWait;

  /// The requests answered (or being answered) in this run: a button delivered twice — at a launch and again on
  /// a resume — answers once.
  final _answered = <String>{};

  /// Never throws.
  Future<void> answer(PushMessage message, PushAnswer answer) async {
    try {
      if (!_answered.add('${answer.agentId} ${answer.sid} ${answer.permission}')) return;
      if (!await _whenUnlocked()) return; // R7: nothing is sent, nothing opens
      final backend = _session.backend.peek();
      if (backend == null) return;
      final pinned = await backend.pinnedMachines();
      if (!pinned.any((machine) => machine.agentId == answer.agentId)) return;
      if (!identical(_session.backend.peek(), backend)) return;
      final (text, tone) = await _send(backend, answer);
      await _opener.open(message);
      _say(text, tone);
    } catch (error) {
      if (kDebugMode) debugPrint('PushAnswerer error: ${error.runtimeType}');
    }
  }

  /// R7: true once the app is in the foreground and its lock is open; false — the answer is dropped — when an
  /// unlock attempt ends with the app still locked (cancelled, failed), when the app leaves the foreground while
  /// it waits, or after [patience].
  Future<bool> _whenUnlocked() {
    final done = Completer<bool>();
    void Function()? stop;
    Timer? timer;
    var wasForeground = false;
    var wasAuthenticating = false;
    void finish(bool ok) {
      if (done.isCompleted) return;
      timer?.cancel();
      done.complete(ok);
      // Not from inside the effect, which may be running now.
      scheduleMicrotask(() => stop?.call());
    }

    timer = Timer(patience, () => finish(false));
    stop = effect(() {
      final foreground = _lock.inForeground.value;
      final locked = _lock.isLocked.value;
      final authenticating = _lock.isAuthenticating.value;
      if (done.isCompleted) return;
      if (wasForeground && !foreground) {
        finish(false);
        return;
      }
      if (wasAuthenticating && !authenticating && locked) {
        finish(false);
        return;
      }
      wasForeground = wasForeground || foreground;
      wasAuthenticating = authenticating;
      if (foreground && !locked && !authenticating) finish(true);
    });
    return done.future;
  }

  /// Sends the one answer and says how it ended. Before it goes, the relay and the computer must answer: a
  /// failure there sent nothing, and says why in the machine's words.
  Future<(String, _Tone)> _send(ShellxBackend backend, PushAnswer answer) async {
    final s = _words();
    final MachineSession machine;
    try {
      machine = backend.machine(answer.agentId);
    } on StateError {
      return (AiWords.machineFailure(s, MachineConnectionFailure.untrusted), _Tone.problem);
    }
    if (!await _relayConnected(backend)) {
      return (AiWords.machineFailure(s, MachineConnectionFailure.timeout), _Tone.problem);
    }
    try {
      await machine.connect();
    } on MachineConnectionException catch (error) {
      return (AiWords.machineFailure(s, error.failure), _Tone.problem);
    }
    try {
      await machine.ai.answerPermission(answer.sid, answer.permission, answer.option);
      final task = answer.task ?? '';
      return (answer.allow ? s.aiPushAllowed(task) : s.aiPushDenied(task), _Tone.done);
    } on AiRequestException catch (error) {
      return (
        switch (error.code) {
          // Answered on the computer or on another phone, or no longer asked: nothing else is answered (B10).
          'stale' => s.aiPushAnsweredElsewhere,
          // The session closed — or the push is of a run before the computer restarted (B23: the session page
          // that opens next finds it again when it can).
          'not_found' || 'gone' => s.aiClosedGone,
          'on_computer' => s.aiPermOnComputer,
          'unavailable' => s.aiUnavailable,
          final code => AiWords.failure(s, code, answer: true) ?? s.aiRequestFailed(code),
        },
        _Tone.note,
      );
    } on MachineConnectionException catch (error) {
      return (
        switch (error.failure) {
          // It may have gone: never sent again (V2-2 D13).
          MachineConnectionFailure.agentOffline || MachineConnectionFailure.timeout => s.aiPushMaybeNotSent,
          final failure => AiWords.machineFailure(s, failure),
        },
        _Tone.problem,
      );
    }
  }

  /// A launch from the push: the relay may still be connecting.
  Future<bool> _relayConnected(ShellxBackend backend) async {
    if (backend.relayState == RelayConnectionState.connected) return true;
    try {
      await backend.relayStates.firstWhere((state) => state == RelayConnectionState.connected).timeout(relayWait);
      return true;
    } on Object {
      return false;
    }
  }

  void _say(String text, _Tone tone) {
    try {
      final popup = _popup();
      switch (tone) {
        case _Tone.done:
          popup.showSuccess(title: text);
        case _Tone.note:
          popup.showInfo(title: text);
        case _Tone.problem:
          popup.showError(title: text);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('PushAnswerer toast error: ${error.runtimeType}');
    }
  }
}
