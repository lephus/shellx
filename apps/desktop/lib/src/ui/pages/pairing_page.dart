import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/desktop_services.dart';
import '../form_rules.dart';

/// QR pairing window (spec §5.3): QR of the pairing URI and a countdown to
/// expiry. Closing the window invalidates the code (see WindowRouter).
class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(agentControllerProvider);
    final now = ref.watch(clockProvider)();
    final pairing = state.pairing;
    final remaining = pairing?.expiresAt.difference(now) ?? Duration.zero;
    final expired = pairing == null || remaining <= Duration.zero;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.pairingTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.pairingInstructions),
          const SizedBox(height: 16),
          Center(
            child: SizedBox.square(
              dimension: 260,
              child: expired
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.pairingExpired,
                            key: const Key('pairing.expired'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('pairing.new'),
                            onPressed: () => ref
                                .read(agentControllerProvider.notifier)
                                .startPairing(),
                            child: Text(l10n.pairingNewCode),
                          ),
                        ],
                      ),
                    )
                  : QrImageView(
                      key: const Key('pairing.qr'),
                      data: pairing.uri.toUriString(),
                      size: 260,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (!expired)
            Text(
              l10n.pairingExpiresIn(formatCountdown(remaining)),
              key: const Key('pairing.countdown'),
              textAlign: TextAlign.center,
            ),
          if (state.relay != RelayConnectionState.connected) ...[
            const SizedBox(height: 12),
            Text(
              l10n.pairingOfflineWarning,
              key: const Key('pairing.offline'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const Spacer(),
          Text(l10n.pairingSecretWarning, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
