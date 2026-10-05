import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal_sharing/attach_throttle.dart';

DesktopSessionSummary summary({
  String app = 'Terminal',
  String title = 'build',
  String shell = 'zsh',
}) => DesktopSessionSummary(
  id: 1,
  index: 1,
  app: app,
  title: title,
  shell: shell,
  createdAt: DateTime(2026),
  attachedMobileId: null,
  connected: true,
);

void main() {
  group('AttachNotificationThrottle', () {
    test('one notification per (phone, terminal) per 10 minutes', () {
      var now = DateTime(2026, 10, 5, 12);
      final throttle = AttachNotificationThrottle(now: () => now);
      expect(throttle.allow('m1', 1), isTrue);
      expect(throttle.allow('m1', 1), isFalse);
      // Another terminal or another phone is a different pair.
      expect(throttle.allow('m1', 2), isTrue);
      expect(throttle.allow('m2', 1), isTrue);

      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(throttle.allow('m1', 1), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(throttle.allow('m1', 1), isTrue);
      expect(throttle.allow('m1', 1), isFalse);
    });
  });

  group('desktopTerminalLabel', () {
    test('app — title, falling back to the shell and to "Terminal"', () {
      expect(desktopTerminalLabel(summary()), 'Terminal — build');
      expect(desktopTerminalLabel(summary(title: '')), 'Terminal — zsh');
      expect(
        desktopTerminalLabel(summary(app: '', title: 'vim')),
        'Terminal — vim',
      );
      expect(desktopTerminalLabel(summary(title: '', shell: '')), 'Terminal');
    });
  });

  group('terminalSharingAvailable', () {
    test('macOS always; Windows only with SHELLX_EXPERIMENTAL', () {
      expect(
        terminalSharingAvailable(macos: true, windows: false, environment: {}),
        isTrue,
      );
      expect(
        terminalSharingAvailable(macos: false, windows: true, environment: {}),
        isFalse,
      );
      expect(
        terminalSharingAvailable(
          macos: false,
          windows: true,
          environment: {'SHELLX_EXPERIMENTAL': 'terminal-sharing'},
        ),
        isTrue,
      );
      expect(
        terminalSharingAvailable(
          macos: false,
          windows: true,
          environment: {'SHELLX_EXPERIMENTAL': 'other, Terminal-Sharing'},
        ),
        isTrue,
      );
      expect(
        terminalSharingAvailable(
          macos: false,
          windows: true,
          environment: {'SHELLX_EXPERIMENTAL': 'other'},
        ),
        isFalse,
      );
      expect(
        terminalSharingAvailable(macos: false, windows: false, environment: {}),
        isFalse,
      );
    });
  });
}
