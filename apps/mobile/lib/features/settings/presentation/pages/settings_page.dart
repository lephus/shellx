import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/biometric_method.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/settings_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #5 and the design's "Cài đặt": grouped cards — Terminal (font size with a live
/// preview), Security (biometric lock), paired computers, account — and the version footer
/// (it opens the open-source licences, incl. both fonts' OFL).
@RoutePage()
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsController _controller = getIt<SettingsController>();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unpair(PairedMachine machine) async {
    final strings = S.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: strings.settingsUnpairConfirm(machine.name ?? strings.unknownMachine),
      confirmLabel: strings.settingsUnpair,
    );
    if (confirmed) await _controller.unpair(machine.agentId);
  }

  Future<void> _logout() async {
    final strings = S.of(context);
    final confirmed = await showConfirmDialog(
      context,
      message: strings.settingsLogoutConfirm,
      confirmLabel: strings.settingsLogout,
    );
    if (confirmed) await _controller.logout();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final settings = _controller.settings;
    final version = strings.settingsVersion(_controller.version, _controller.buildNumber);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Group(
            header: strings.settingsTerminalGroup,
            children: [
              Watch((context) {
                final fontSize = settings.fontSize.value;
                return Column(
                  children: [
                    _Row(
                      title: strings.settingsFontSize,
                      trailing: Text(
                        fontSize.toStringAsFixed(0),
                        style: context.typo.paragraph.copyWith(color: colors.secondaryText),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Row(
                        children: [
                          Text('A', style: context.typo.metadata11.copyWith(color: colors.disable)),
                          Expanded(
                            child: Slider(
                              min: AppSettings.minFontSize,
                              max: AppSettings.maxFontSize,
                              divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
                              value: fontSize,
                              label: fontSize.toStringAsFixed(0),
                              // The preview follows every step; the size is stored once, on release.
                              onChanged: _controller.previewFontSize,
                              onChangeEnd: _controller.setFontSize,
                            ),
                          ),
                          Text('A', style: context.typo.title.copyWith(color: colors.disable)),
                        ],
                      ),
                    ),
                    _FontPreview(fontSize: fontSize),
                  ],
                );
              }),
            ],
          ),
          _Group(
            header: strings.settingsSecurityGroup,
            footer: Watch(
              (context) => Text(
                _controller.biometricsAvailable.value
                    ? strings.settingsLockFootnote
                    : strings.settingsBiometricUnavailable,
                style: context.typo.metadata12.copyWith(color: colors.disable),
              ),
            ),
            children: [
              Watch((context) {
                final available = _controller.biometricsAvailable.value;
                return SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15),
                  title: Text(
                    strings.settingsLockWith(biometricMethod(strings, _controller.lockKind.value)),
                    style: context.typo.subHeader15,
                  ),
                  value: available && settings.biometricLock.value,
                  onChanged: available ? _controller.setBiometricLock : null,
                );
              }),
            ],
          ),
          _Group(
            header: strings.settingsPairedMachines,
            children: [
              Watch((context) {
                final machines = _controller.paired.value;
                final failedIds = _controller.failedUnpair.value;
                if (machines == null) {
                  return const Padding(padding: EdgeInsets.all(15), child: AppCircularProgress(size: 24));
                }
                if (machines.isEmpty) return _Row(title: strings.settingsNoPairedMachines, muted: true);
                return Column(
                  children: [
                    for (final (i, machine) in machines.indexed) ...[
                      if (i > 0) Divider(height: 1, color: colors.divider),
                      if (failedIds.contains(machine.agentId))
                        _FailedRow(
                          title: machine.name ?? strings.unknownMachine,
                          onRetry: () => _controller.unpair(machine.agentId),
                        )
                      else
                        _Row(
                          title: machine.name ?? strings.unknownMachine,
                          trailing: TextButton(
                            onPressed: () => _unpair(machine),
                            child: Text(
                              strings.settingsUnpair,
                              style: context.typo.paragraph.bold.copyWith(color: colors.error),
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              }),
            ],
          ),
          _Group(
            header: strings.settingsAccountGroup,
            footer: Center(
              child: GestureDetector(
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: strings.appTitle,
                  applicationVersion: '${_controller.version} (${_controller.buildNumber})',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(version, style: context.typo.metadata12.copyWith(color: colors.disable)),
                ),
              ),
            ),
            children: [
              _Row(
                title: strings.settingsEmail,
                trailing: Text(_controller.email, style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
              ),
              Divider(height: 1, color: colors.divider),
              Watch((context) {
                final loggingOut = _controller.loggingOut.value;
                return _Row(
                  title: strings.settingsLogout,
                  leading: Icon(Icons.logout, color: loggingOut ? colors.disable : colors.secondaryText),
                  onTap: loggingOut ? null : _logout,
                );
              }),
              Divider(height: 1, color: colors.divider),
              Watch((context) {
                final loggingOut = _controller.loggingOut.value;
                return _Row(
                  title: strings.settingsDeleteAccount,
                  leading: Icon(Icons.delete_outline, color: loggingOut ? colors.disable : colors.error),
                  danger: true,
                  onTap: loggingOut ? null : () => context.router.push(const DeleteAccountRoute()),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

/// `.grp`: an upper-case header, a rounded card and an optional footnote.
class _Group extends StatelessWidget {
  const _Group({required this.header, required this.children, this.footer});

  final String header;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
            child: Text(
              header.toUpperCase(),
              style: context.typo.paragraph13.bold.copyWith(color: colors.secondaryText, letterSpacing: 0.8),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(6, 7, 6, 0), child: footer),
        ],
      ),
    );
  }
}

/// `.ri`: one 50 pt row of a settings card.
class _Row extends StatelessWidget {
  const _Row({required this.title, this.leading, this.trailing, this.onTap, this.danger = false, this.muted = false});

  final String title;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = danger
        ? context.typo.subHeader15.bold.copyWith(color: colors.error)
        : context.typo.subHeader15.copyWith(color: muted ? colors.secondaryText : colors.primaryText);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              if (leading != null) ...[leading!, 10.sizedWidth],
              Expanded(child: Text(title, style: style)),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A machine whose unpair failed after the pin was already dropped (spec §5.5): the row stays,
/// with the failed text under the name and a retry instead of the "Bỏ ghép nối" action.
class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.title, required this.onRetry});

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.typo.subHeader15.copyWith(color: colors.primaryText)),
                  Text(
                    strings.settingsUnpairFailed,
                    style: context.typo.metadata12.copyWith(color: colors.secondaryText),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(strings.retry, style: context.typo.paragraph.bold.copyWith(color: colors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A prompt in the terminal font at the chosen size (design `.preview`).
class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: FontFamily.jetBrainsMono, fontSize: fontSize, height: 1.3);
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 0, 15, 14),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: TerminalColors.background, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(
        TextSpan(
          style: style.copyWith(color: TerminalColors.foreground),
          children: const [
            TextSpan(
              text: 'user@macbook',
              style: TextStyle(color: TerminalColors.green),
            ),
            TextSpan(text: ' '),
            TextSpan(
              text: '~',
              style: TextStyle(color: TerminalColors.cyan),
            ),
            TextSpan(
              text: ' % ',
              style: TextStyle(color: TerminalColors.dim),
            ),
            TextSpan(text: 'ls'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
      ),
    );
  }
}
