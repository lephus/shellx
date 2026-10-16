import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

class AppErrorWidget extends StatefulWidget {
  final AppError? error;
  final Future Function()? retry;
  const AppErrorWidget({
    super.key,
    this.error,
    this.retry,
  });

  @override
  State<AppErrorWidget> createState() => _AppErrorWidgetState();
}

class _AppErrorWidgetState extends State<AppErrorWidget> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(widget.error?.title ?? S.of(context).somethingWentWrong),
          12.sizedHeight,
          if (widget.retry != null)
            AppButton(
              backgroundColor: context.colors.primaryFill,
              // onPrimary: white in light (5.3:1), dark ink on dark primary (7.0:1; white was 2.2:1).
              textColor: context.colors.onPrimary,
              title: S.of(context).retry,
              prefix: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.refresh, color: context.colors.onPrimary),
              ),
              onTap: widget.retry,
            ),
        ],
      ),
    );
  }
}
