import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2 §5.1 "Phiên AI mới": an agent and a folder, both from what the
/// computer offers (V2-2 D9: never a path typed on the phone). Null when
/// dismissed.
Future<({String agent, String folder})?> showAiNewSessionSheet(BuildContext context, AiListing listing) {
  return showModalBottomSheet<({String agent, String folder})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (context) => _NewSessionSheet(listing: listing),
  );
}

/// What the user chose lives in this state, not in the route's builder: the builder runs again when
/// the phone is turned, and the choice must not go back to the default then.
class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet({required this.listing});

  final AiListing listing;

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  late String? _agent = _firstAgent();
  late String? _folder = widget.listing.folders.isEmpty ? null : widget.listing.folders.first.key;

  /// The computer's default agent when it is ready, else the first one that is.
  String? _firstAgent() {
    final ready = [
      for (final a in widget.listing.agents)
        if (a.ready) a,
    ];
    if (ready.any((a) => a.id == widget.listing.defaultAgent)) return widget.listing.defaultAgent;
    return ready.isEmpty ? null : ready.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final s = S.of(context);
    final colors = context.colors;
    final agent = _agent;
    final folder = _folder;
    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: context.typo.paragraph13.bold.copyWith(color: colors.secondaryText, letterSpacing: 0.8),
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.aiNewSession, style: context.typo.heading20.heavy),
            header(s.aiNewAgent),
            RadioGroup<String>(
              groupValue: agent,
              onChanged: (v) => setState(() => _agent = v),
              child: Column(
                children: [
                  for (final a in listing.agents)
                    RadioListTile<String>(
                      key: ValueKey('ai-new-agent-${a.id}'),
                      contentPadding: EdgeInsets.zero,
                      value: a.id,
                      enabled: a.ready,
                      title: Text(a.name),
                      subtitle: a.ready ? null : Text(s.aiAgentNotReady),
                    ),
                ],
              ),
            ),
            header(s.aiNewFolder),
            RadioGroup<String>(
              groupValue: folder,
              onChanged: (v) => setState(() => _folder = v),
              child: Column(
                children: [
                  for (final f in listing.folders)
                    RadioListTile<String>(
                      key: ValueKey('ai-new-folder-${f.key}'),
                      contentPadding: EdgeInsets.zero,
                      value: f.key,
                      title: Text(f.name),
                      subtitle: f.path == null ? null : Text(f.path!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            16.sizedHeight,
            AppButton(
              key: const ValueKey('ai-new-start'),
              title: s.aiNewStart,
              state: agent == null || folder == null ? ButtonState.disable : ButtonState.available,
              onTap: () => Navigator.pop(context, (agent: agent!, folder: folder!)),
            ),
          ],
        ),
      ),
    );
  }
}
