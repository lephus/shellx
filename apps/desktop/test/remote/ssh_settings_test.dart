import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/remote/ssh_settings.dart';

void main() {
  test('the SSH keys are allowed settings (D6, D11)', () {
    expect(
      SettingKeys.all,
      containsAll([
        SettingKeys.sshRecentTargets,
        SettingKeys.sshPlainTargets,
        SettingKeys.sshRemoteHook,
      ]),
    );
  });

  test(
    'recent targets keep only canonical keys, never raw text (T1 carry)',
    () async {
      final s = InMemorySettingsStore();
      await s.setStrings(SettingKeys.sshRecentTargets, [
        'devbox',
        'ssh://x',
        '-oProxyCommand=y',
        ' pad ',
        'me@h:22',
      ]);
      expect([for (final t in recentTargets(s)) t.key], ['devbox', 'me@h:22']);
    },
  );
}
