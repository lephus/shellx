import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../window_router.dart';

class ConfirmPage extends StatelessWidget {
  const ConfirmPage({super.key, required this.request});

  final ConfirmRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Expanded(
            child: Text(request.body, style: theme.textTheme.bodyMedium),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('confirm.cancel'),
                onPressed: () => request.complete(false),
                child: Text(l10n.actionCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('confirm.ok'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: () => request.complete(true),
                child: Text(request.confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
