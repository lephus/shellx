import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

abstract class InterfacePaginationView extends StatefulWidget {
  final PagingStateSignal pagingState;
  final EdgeInsets? padding;
  final Widget Function(BuildContext, int) itemBuilder;
  final Widget Function(BuildContext, int)? separatorBuilder;
  final Widget? emptyView;
  final Widget? noMoreItemsView;
  final Future Function()? refresh;

  const InterfacePaginationView({
    super.key,
    required this.pagingState,
    required this.itemBuilder,
    this.separatorBuilder,
    this.emptyView,
    this.padding,
    this.noMoreItemsView,
    this.refresh,
  });
}

class FirstPageError extends StatefulWidget {
  final Object? error;
  final Future Function()? onTryAgain;
  const FirstPageError({
    super.key,
    required this.error,
    this.onTryAgain,
  });

  @override
  State<FirstPageError> createState() => _FirstPageErrorState();
}

class _FirstPageErrorState extends State<FirstPageError> {
  bool isLoading = false;
  Future<void> retry() async {
    setState(() {
      isLoading = true;
    });
    await widget.onTryAgain?.call();
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              S.of(context).somethingWentWrongPleaseTryAgain,
              textAlign: TextAlign.center,
              style: context.typo.subHeader15.medium,
            ),
          ),
          if (widget.onTryAgain != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: retry,
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: isLoading ? 0 : 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                color: context.colors.white,
                              ),
                              SizedBox(
                                width: 8,
                              ),
                              Text(
                                'Retry',
                                style: TextStyle(
                                  color: context.colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: Visibility(
                            visible: isLoading,
                            child: Center(
                              child: CircularProgressIndicator.adaptive(
                                valueColor: AlwaysStoppedAnimation<Color>(context.colors.white),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NewPageError extends StatelessWidget {
  final VoidCallback onTryAgain;
  const NewPageError({super.key, required this.onTryAgain});

  @override
  Widget build(BuildContext context) {
    return AppRefresh(
      onRefresh: () => Future.sync(
        () => onTryAgain(),
      ),
      child: Center(
        child: ItemNotFound(
          message: S.of(context).somethingWentWrong,
        ),
      ),
    );
  }
}

class FirstPageProgress extends StatelessWidget {
  final double radius;
  const FirstPageProgress({super.key, this.radius = 24.0});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: AppCircularProgress(),
    );
  }
}

class NewPageProgress extends StatelessWidget {
  final double radius;
  const NewPageProgress({super.key, this.radius = 22.0});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 36,
        horizontal: 16,
      ),
      child: Center(
        child: AppCircularProgress(),
      ),
    );
  }
}

class NoMoreItems extends StatelessWidget {
  const NoMoreItems({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 16.0);
  }
}

class FirstPageEmptyView extends StatelessWidget {
  final String message;
  final double aspectRatio;
  const FirstPageEmptyView({
    super.key,
    required this.message,
    this.aspectRatio = 3 / 2,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

mixin PagingStateMixin<T extends InterfacePaginationView> on State<T> {
  late final pagingState = widget.pagingState;
}
