/// AI sessions as a paired phone sees them (V2-2): the listing, the mirror
/// wire format, the desktop's per-phone [AiSubscription] and the phone's
/// [AiMirror]. Pure Dart: no file, process or socket access, no Flutter.
library;

export 'src/remote/acp_out.dart';
export 'src/remote/item_codec.dart' show encodeHead, encodeItem, itemText;
export 'src/remote/listing.dart';
export 'src/remote/mirror.dart';
export 'src/remote/no_approval.dart';
export 'src/remote/subscription.dart';
export 'src/remote/undo_view.dart';
export 'src/remote/wire.dart'
    show
        clipText,
        decodeBody,
        encodeBody,
        jBool,
        jInt,
        jMap,
        jMaps,
        jString,
        jStrings,
        kAiAttachItems,
        kAiBodyBytes,
        kAiPageItems,
        kAiRecordBytes,
        kAiWindowBytes,
        kAiWireVersion,
        utf8Length;
