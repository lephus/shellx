import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §12/§14 and the design's "Lệch phiên bản": `/v1/version` is newer than the app, or a
/// machine answered `proto_unsupported`. The button opens the store of this platform.
@RoutePage()
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              const StatusCircle(icon: Icons.system_update_alt, tone: StatusTone.warn),
              16.sizedHeight,
              Text(strings.updateRequiredTitle, style: context.typo.heading26.heavy),
              12.sizedHeight,
              Text(
                strings.updateRequiredBody,
                textAlign: TextAlign.center,
                style: context.typo.subHeader15.copyWith(color: context.colors.secondaryText),
              ),
              const Spacer(),
              AppButton(
                title: ios ? strings.openAppStore : strings.openPlayStore,
                width: double.infinity,
                onTap: () => getIt<ExternalLinks>().openOrToast(ios ? AppConfig.appStorePage : AppConfig.playStorePage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
