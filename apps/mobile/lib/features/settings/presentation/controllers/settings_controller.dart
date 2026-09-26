import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// A computer pinned on this phone; [name] is null while `GET /v1/devices` is unreachable.
typedef PairedMachine = ({String agentId, String? name});

/// Spec §9.2 #5: default font size, biometric lock, unpair per machine, sign out, version.
@injectable
class SettingsController extends Controller {
  SettingsController(
    this._session,
    this.settings,
    this._lock,
    this._biometrics,
    this._registry,
    this._packageInfo,
    this._pendingUnpairs,
  );

  final SessionHolder _session;
  final AppSettings settings;
  final AppLockController _lock;
  final BiometricAuthenticator _biometrics;
  final WorkspaceRegistry _registry;
  final PackageInfo _packageInfo;
  final PendingUnpairs _pendingUnpairs;
  final Signal<bool> _biometricsAvailable = signal(false);
  final Signal<List<PairedMachine>?> _paired = signal(null);
  final Signal<Set<String>> _failedUnpair = signal(const {});
  final Signal<bool> _loggingOut = signal(false);

  /// Spec §5.5: a machine whose DELETE failed after its pin was already dropped — kept here (with
  /// the name last known for it) so it stays visible with a retry until the DELETE succeeds. The
  /// same entries are persisted in [PendingUnpairs], so they survive leaving Settings; this map
  /// also keeps one whose record could not be written.
  final Map<String, String?> _failedNames = {};
  bool _disposed = false;

  String get email => _session.session.peek()?.email ?? '';
  String get version => _packageInfo.version;
  String get buildNumber => _packageInfo.buildNumber;

  /// Face ID, Touch ID, fingerprint… — names the switch ("Khóa bằng Face ID").
  ReadonlySignal<BiometricKind> get lockKind => _lock.kind;

  /// False when the device has no passcode and no biometrics: the switch is disabled.
  ReadonlySignal<bool> get biometricsAvailable => _biometricsAvailable;

  /// Pinned machines with their names, plus any machine whose unpair failed after its pin was
  /// already dropped (still listed until a retry succeeds); null while loading.
  ReadonlySignal<List<PairedMachine>?> get paired => _paired;

  /// Agent ids of the machines in [paired] whose unpair failed and can be retried.
  ReadonlySignal<Set<String>> get failedUnpair => _failedUnpair;

  /// True while [logout] is in flight; the page disables "Đăng xuất" so a second tap cannot start
  /// another sign-out.
  ReadonlySignal<bool> get loggingOut => _loggingOut;

  Future<void> load() async {
    await guard(() async {
      final available = await _biometrics.isAvailable();
      if (_disposed) return;
      _biometricsAvailable.value = available;
    });
    if (_disposed) return;
    await _loadPaired();
  }

  /// `backend.pinnedMachines()` reads secure storage and can throw (Keychain/Keystore error): the
  /// whole reload is guarded, so the toast shows and the page never spins forever. On that
  /// failure, [paired] falls back to whatever is already known to have failed to unpair, or an
  /// empty list — never null again once [load] has run once.
  Future<void> _loadPaired() async {
    await _loadPending();
    if (_disposed) return;
    await guard(() async {
      final backend = _session.requireBackend;
      final List<PinnedMachine> pins;
      try {
        pins = await backend.pinnedMachines();
      } catch (_) {
        if (!_disposed) _showFailedOnly();
        rethrow;
      }
      if (_disposed) return;
      var names = <String, String>{};
      try {
        names = {for (final device in await backend.devices()) device.id: device.name};
      } on Object {
        // Offline: still list the pinned machines, without names.
      }
      if (_disposed) return;
      final pinnedIds = pins.map((pin) => pin.agentId).toSet();
      // A machine that got paired again (fresh pin) is no longer a failed unpair.
      final pairedAgain = _failedNames.keys.where(pinnedIds.contains).toList();
      for (final agentId in pairedAgain) {
        _failedNames.remove(agentId);
        await _forgetPending(agentId);
      }
      if (_disposed) return;
      final combined = [
        for (final pin in pins) (agentId: pin.agentId, name: names[pin.agentId]),
        for (final entry in _failedNames.entries) (agentId: entry.key, name: entry.value),
      ];
      batch(() {
        _paired.value = combined;
        _failedUnpair.value = Set.unmodifiable(_failedNames.keys);
      });
    });
  }

  /// The unpairs still pending from earlier visits (or another start) become failed rows too.
  Future<void> _loadPending() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      for (final entry in await _pendingUnpairs.load(userId)) {
        _failedNames.update(entry.agentId, (name) => name ?? entry.name, ifAbsent: () => entry.name);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('SettingsController pending unpairs error: ${error.runtimeType}');
    }
  }

  String? get _userId => _session.session.peek()?.userId;

  /// Best effort: the row is shown from [_failedNames] even when the record cannot be written.
  Future<void> _rememberPending(String? userId, String agentId, String? name) async {
    if (userId == null) return;
    try {
      await _pendingUnpairs.add(userId, agentId, name);
    } catch (error) {
      if (kDebugMode) debugPrint('SettingsController pending unpairs error: ${error.runtimeType}');
    }
  }

  Future<void> _forgetPending(String agentId, [String? userId]) async {
    userId ??= _userId;
    if (userId == null) return;
    try {
      await _pendingUnpairs.remove(userId, agentId);
    } catch (error) {
      if (kDebugMode) debugPrint('SettingsController pending unpairs error: ${error.runtimeType}');
    }
  }

  void _showFailedOnly() => batch(() {
    _paired.value = [for (final entry in _failedNames.entries) (agentId: entry.key, name: entry.value)];
    _failedUnpair.value = Set.unmodifiable(_failedNames.keys);
  });

  String? _nameOf(String agentId) {
    for (final machine in _paired.peek() ?? const <PairedMachine>[]) {
      if (machine.agentId == agentId) return machine.name;
    }
    return null;
  }

  /// While the slider moves: the preview follows, nothing is written yet.
  void previewFontSize(double size) => settings.previewFontSize(size);

  /// When the slider is released: the size is stored; a failed write shows the toast.
  Future<void> setFontSize(double size) => guard(() => settings.setFontSize(size));

  /// The lock follows the setting only once it is stored; a failed write shows the toast and
  /// leaves both as they were.
  Future<void> setBiometricLock(bool enabled) => guard(() async {
    await settings.setBiometricLock(enabled);
    _lock.settingChanged();
  });

  /// Spec §5.5: drop the pin and the pairing record, and the machine's open tabs. The real
  /// `unpair` shuts the machine down and forgets the pin before its DELETE, which can still throw
  /// (network, 5xx): the workspace is dropped either way (in a `finally`), but a machine whose
  /// DELETE failed is kept — with the name known for it — in [PendingUnpairs] and on this page,
  /// so its row stays with a retry, also after leaving Settings, and the next start retries it.
  Future<void> unpair(String agentId) async {
    final name = _nameOf(agentId);
    final userId = _userId;
    var failed = false;
    await guard(() async {
      try {
        await _session.requireBackend.unpair(agentId);
      } catch (_) {
        failed = true;
        rethrow;
      } finally {
        _registry.remove(agentId);
      }
    });
    // Recorded even when the page was left meanwhile: that is what the record is for.
    if (failed) {
      _failedNames[agentId] = name;
      await _rememberPending(userId, agentId, name);
    } else {
      _failedNames.remove(agentId);
      await _forgetPending(agentId, userId);
    }
    if (_disposed) return;
    await _loadPaired();
  }

  /// Only the token is deleted (spec §5.2); `SessionEnforcer` returns to the login page. Guarded
  /// against overlapping with a deletion: a second call while one is in flight is a no-op, and the
  /// page disables "Đăng xuất" for the same reason.
  Future<void> logout() async {
    if (_loggingOut.peek()) return;
    _loggingOut.value = true;
    try {
      await _session.logout();
    } finally {
      if (!_disposed) _loggingOut.value = false;
    }
  }

  void dispose() {
    _disposed = true;
    _biometricsAvailable.dispose();
    _paired.dispose();
    _failedUnpair.dispose();
    _loggingOut.dispose();
  }
}
