import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/mux/launch_mode.dart';

void main() {
  test('launch modes', () {
    expect(parseLaunchMode(const []), LaunchMode.ui);
    expect(parseLaunchMode(const ['--daemon']), LaunchMode.daemon);
    expect(
      parseLaunchMode(const ['--terminal-sharing-cleanup']),
      LaunchMode.terminalSharingCleanup,
    );
    expect(parseLaunchMode(const ['-psn_0_12345']), LaunchMode.ui); // Finder
  });
}
