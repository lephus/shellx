import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Placeholder home of the scaffold. Task 19 deletes it when the ShellX routes arrive.
@RoutePage()
class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(S.of(context).appTitle, style: context.typo.heading28.bold),
      ),
    );
  }
}
