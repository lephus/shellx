import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_attachments.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2b B12: where the photos of the next message come from — "Thư viện ảnh" or "Chụp ảnh". Null when dismissed.
Future<AiImageOrigin?> showAiAttachSheet(BuildContext context) => showModalBottomSheet<AiImageOrigin>(
  context: context,
  showDragHandle: true,
  backgroundColor: context.colors.surface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
  builder: (context) {
    final s = S.of(context);
    final colors = context.colors;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('ai.attach.library'),
            leading: Icon(Icons.photo_library_outlined, color: colors.primary),
            title: Text(s.aiAttachPhoto, style: context.typo.subHeader15),
            onTap: () => Navigator.pop(context, AiImageOrigin.library),
          ),
          ListTile(
            key: const Key('ai.attach.camera'),
            leading: Icon(Icons.photo_camera_outlined, color: colors.primary),
            title: Text(s.aiTakePhoto, style: context.typo.subHeader15),
            onTap: () => Navigator.pop(context, AiImageOrigin.camera),
          ),
          8.sizedHeight,
        ],
      ),
    );
  },
);
