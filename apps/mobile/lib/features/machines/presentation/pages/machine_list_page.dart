import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #2 / §12 and the design's "Máy của bạn": online machines first, an "Offline" group
/// (dimmed, not tappable), "Chưa ghép nối" opens the scanner, "N tab" counts the tabs open on this
/// phone; the first run shows three pairing steps.
@RoutePage()
class MachineListPage extends StatefulWidget {
  const MachineListPage({super.key});

  @override
  State<MachineListPage> createState() => _MachineListPageState();
}

class _MachineListPageState extends State<MachineListPage> {
  final MachineListController _controller = getIt<MachineListController>();

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pairing, unpairing and new tabs happen on the pushed pages: refresh when they close.
  Future<void> _then(Future<Object?> navigation) async {
    await navigation;
    if (mounted) await _controller.refresh();
  }

  Future<void> _scan() => _then(context.router.push(QrScannerRoute()));

  Future<void> _open(MachineEntry machine) async {
    final exit = await context.router.push<TerminalExit>(TerminalRoute(agentId: machine.id, machineName: machine.name));
    if (!mounted) return;
    await _controller.refresh();
    if (!mounted) return;
    switch (exit) {
      case TerminalExit.untrusted:
        await _askToPairAgain();
      case TerminalExit.updateRequired:
        await context.router.push(const UpdateRequiredRoute());
      case null:
        break;
    }
  }

  /// Design "Máy đã thu hồi điện thoại": the pin is already gone; offer to scan again.
  Future<void> _askToPairAgain() async {
    final strings = S.of(context);
    final scan = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.untrustedTitle, textAlign: TextAlign.center, style: context.typo.title.bold),
        content: Text(
          strings.errorUntrusted,
          textAlign: TextAlign.center,
          style: context.typo.paragraph.copyWith(color: context.colors.secondaryText),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(strings.actionLater)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(strings.actionScanCode, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (scan == true && mounted) await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: strings.settingsTooltip,
                  icon: Icon(Icons.settings_outlined, color: context.colors.primary),
                  onPressed: () => _then(context.router.push(const SettingsRoute())),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(strings.machinesTitle, style: context.typo.display32.heavy),
            ),
            ConnectionBanner(
              backend: _controller.backend,
              onReconnectReplaced: _controller.reconnectReplaced,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            ),
            Expanded(
              child: Watch((context) {
                final state = _controller.state;
                final machines = state.value.machines;
                if (!state.isLoading && !state.hasError && machines.isEmpty) {
                  return _EmptyState(onScan: _scan);
                }
                final waiting = _controller.waiting.value;
                final online = machines.where((m) => m.online).toList();
                final offline = machines.where((m) => !m.online).toList();
                MachineCard card(MachineEntry machine) => MachineCard(
                  machine: machine,
                  waiting: waiting,
                  tabs: _controller.tabsOpen(machine.id),
                  now: _controller.now(),
                  onTap: waiting || !machine.online
                      ? null
                      : machine.paired
                      ? () => _open(machine)
                      : _scan,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AppScrollView(
                        onRefresh: _controller.refresh,
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverOpacity(
                              opacity: waiting ? 0.55 : 1,
                              sliver: SliverList.list(
                                children: [
                                  if (state.isLoading && machines.isEmpty) const LinearProgressIndicator(),
                                  if (state.hasError && state.error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: NoticeBanner(
                                        text: state.error!.title,
                                        leading: const Icon(Icons.error_outline),
                                      ),
                                    ),
                                  for (final machine in online) card(machine),
                                  if (offline.isNotEmpty) _GroupHeader(strings.machinesOfflineHeader),
                                  for (final machine in offline) card(machine),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: AppButton(
                        title: strings.pairNewMachine,
                        backgroundColor: context.colors.primarySoft,
                        textColor: context.colors.primary,
                        prefix: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.qr_code_2, color: context.colors.primary),
                        ),
                        onTap: _scan,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
    child: Text(
      text.toUpperCase(),
      style: context.typo.paragraph13.bold.copyWith(color: context.colors.secondaryText, letterSpacing: 0.8),
    ),
  );
}

/// One computer (`.m`): OS tile, name, status line, "N tab" and the right-hand hint.
class MachineCard extends StatelessWidget {
  const MachineCard({
    super.key,
    required this.machine,
    required this.waiting,
    required this.tabs,
    required this.now,
    required this.onTap,
  });

  final MachineEntry machine;
  final bool waiting;
  final int tabs;
  final DateTime now;

  /// Null when the card cannot be opened (offline, or the relay is reconnecting).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final online = machine.online && !waiting;
    final platform = machine.platform == DevicePlatform.windows ? 'Windows' : 'macOS';
    // A machine that was just paired and has never connected to the relay has no
    // "Lần cuối online" to show; the design is silent on this case, so it reads plain "Offline"
    // (the same word as the group header, not upper-cased).
    final detail = waiting
        ? strings.machineWaiting
        : machine.online
        ? '${strings.machineOnline} · $platform'
        : machine.lastSeenAt == null
        ? strings.machinesOfflineHeader
        : strings.machineLastOnline(formatLastSeen(strings, machine.lastSeenAt, now));
    return Padding(
      key: ValueKey('machine-${machine.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: machine.online ? colors.primarySoft : colors.divider,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    machine.platform == DevicePlatform.windows ? Icons.desktop_windows_outlined : Icons.laptop_mac,
                    color: machine.online ? colors.primary : colors.disable,
                  ),
                ),
                13.sizedWidth,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.name,
                        style: context.typo.subHeader.bold.copyWith(
                          color: machine.online ? colors.primaryText : colors.secondaryText,
                        ),
                      ),
                      3.sizedHeight,
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Container(
                            key: ValueKey(online ? 'dot-online' : 'dot-offline'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: online ? colors.okDot : colors.disable,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(detail, style: context.typo.paragraph13.copyWith(color: colors.secondaryText)),
                          if (tabs > 0 && !waiting)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.divider,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                strings.machineTabs(tabs),
                                style: context.typo.metadata12.bold.copyWith(color: colors.secondaryText),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!machine.paired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: colors.primarySoft, borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      strings.machineNotPaired,
                      style: context.typo.metadata12.bold.copyWith(color: colors.primary),
                    ),
                  )
                else if (onTap != null)
                  Icon(Icons.chevron_right, color: colors.disable),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Design "Lần đầu dùng": the three pairing steps and "Quét mã QR".
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final text = context.typo.subHeader15;
    const site = 'shellx.pro';
    final menu = strings.pairPhoneMenuItem;
    Widget step(int number, Widget body) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.primarySoft, shape: BoxShape.circle),
          child: Text('$number', style: context.typo.paragraph.bold.copyWith(color: colors.primary)),
        ),
        12.sizedWidth,
        Expanded(child: body),
      ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          SizedBox(
            width: 170,
            height: 110,
            child: Stack(
              children: [
                Positioned(left: 0, top: 0, child: Icon(Icons.laptop_mac, size: 118, color: colors.secondaryText)),
                Positioned(right: 4, bottom: 0, child: Icon(Icons.smartphone, size: 64, color: colors.primary)),
              ],
            ),
          ),
          16.sizedHeight,
          Text(strings.emptyTitle, style: context.typo.heading20.heavy),
          16.sizedHeight,
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: [
                step(
                  1,
                  HighlightedText(
                    strings.emptyStep1(site),
                    parts: {site: () => getIt<ExternalLinks>().open(AppConfig.downloadPage)},
                    style: text,
                    partStyle: text.bold.copyWith(color: colors.primary),
                  ),
                ),
                14.sizedHeight,
                step(2, Text(strings.emptyStep2, style: text)),
                14.sizedHeight,
                step(
                  3,
                  HighlightedText(strings.emptyStep3(menu), parts: {menu: null}, style: text, partStyle: text.bold),
                ),
              ],
            ),
          ),
          16.sizedHeight,
          AppButton(
            title: strings.scanQrButton,
            width: double.infinity,
            prefix: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.qr_code_2, color: colors.onPrimary),
            ),
            onTap: onScan,
          ),
        ],
      ),
    );
  }
}
