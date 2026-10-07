/// How this process was started (A5b D2, D3).
enum LaunchMode { ui, daemon, terminalSharingCleanup }

LaunchMode parseLaunchMode(List<String> args) {
  if (args.contains('--daemon')) return LaunchMode.daemon;
  if (args.contains('--terminal-sharing-cleanup')) {
    return LaunchMode.terminalSharingCleanup;
  }
  return LaunchMode.ui;
}
