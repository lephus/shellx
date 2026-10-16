import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b B18: a session whose tab has no folder yet, from the phone: the folders the computer offers (V2-2 D9, never
/// a path typed here), one to pick, and "Dùng thư mục này". The session starts on the computer once it takes it.
class AiFolderChooser extends StatefulWidget {
  const AiFolderChooser({super.key, required this.folders, required this.onUse});

  final List<AiFolderChoice> folders;

  /// The chosen key; completes once the computer answered (the button waits meanwhile).
  final Future<void> Function(String folder) onUse;

  @override
  State<AiFolderChooser> createState() => _AiFolderChooserState();
}

class _AiFolderChooserState extends State<AiFolderChooser> {
  /// The user's pick lives here, not in the page: the computer's list may change while the screen is open, and a
  /// pick that is no longer offered is none.
  late String? _picked = widget.folders.isEmpty ? null : widget.folders.first.key;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final folders = widget.folders;
    final picked = folders.any((f) => f.key == _picked) ? _picked : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.aiChooseFolder, style: context.typo.subHeader15.bold.copyWith(color: colors.primaryText)),
          8.sizedHeight,
          RadioGroup<String>(
            groupValue: picked,
            onChanged: (v) => setState(() => _picked = v),
            child: Column(
              children: [
                for (final f in folders)
                  RadioListTile<String>(
                    key: ValueKey('ai.folder.${f.key}'),
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
            key: const Key('ai.useFolder'),
            title: s.aiUseFolder,
            state: picked == null || _busy ? ButtonState.disable : ButtonState.available,
            onTap: () async {
              setState(() => _busy = true);
              await widget.onUse(picked!);
              if (mounted) setState(() => _busy = false);
            },
          ),
        ],
      ),
    );
  }
}
