import 'acp_json.dart';
import 'json_rpc.dart';

/// A piece of a prompt or message (ACP `ContentBlock`). ShellX sends text,
/// images and resource links (spec D16); embedded resources are read for
/// display; any other type is kept as [OtherBlock] and not drawn.
sealed class ContentBlock with Redacted {
  const ContentBlock();

  static ContentBlock fromJson(JsonMap j) => switch (readString(j, 'type')) {
    'text' => TextBlock(readString(j, 'text') ?? ''),
    'image' => ImageBlock(
      data: readString(j, 'data') ?? '',
      mimeType: readString(j, 'mimeType') ?? '',
      uri: readString(j, 'uri'),
    ),
    'resource_link' => ResourceLinkBlock(
      uri: readString(j, 'uri') ?? '',
      name: readString(j, 'name') ?? '',
      title: readString(j, 'title'),
      mimeType: readString(j, 'mimeType'),
      size: readInt(j, 'size'),
      description: readString(j, 'description'),
    ),
    'resource' => ResourceBlock.fromJson(readMap(j, 'resource') ?? const {}),
    final type => OtherBlock(type),
  };

  JsonMap toJson();
}

final class TextBlock extends ContentBlock {
  const TextBlock(this.text);

  final String text;

  @override
  JsonMap toJson() => {'type': 'text', 'text': text};
}

final class ImageBlock extends ContentBlock {
  const ImageBlock({required this.data, required this.mimeType, this.uri});

  /// Base64 bytes.
  final String data;
  final String mimeType;
  final String? uri;

  @override
  JsonMap toJson() => {
    'type': 'image',
    'data': data,
    'mimeType': mimeType,
    if (uri != null) 'uri': uri,
  };
}

final class ResourceLinkBlock extends ContentBlock {
  const ResourceLinkBlock({
    required this.uri,
    required this.name,
    this.title,
    this.mimeType,
    this.size,
    this.description,
  });

  final String uri;
  final String name;
  final String? title;
  final String? mimeType;
  final int? size;
  final String? description;

  @override
  JsonMap toJson() => {
    'type': 'resource_link',
    'uri': uri,
    'name': name,
    if (title != null) 'title': title,
    if (mimeType != null) 'mimeType': mimeType,
    if (size != null) 'size': size,
    if (description != null) 'description': description,
  };
}

/// An embedded resource; [text] is null for a binary (`blob`) resource.
final class ResourceBlock extends ContentBlock {
  const ResourceBlock({required this.uri, this.text, this.mimeType});

  static ResourceBlock fromJson(JsonMap r) => ResourceBlock(
    uri: readString(r, 'uri') ?? '',
    text: readString(r, 'text'),
    mimeType: readString(r, 'mimeType'),
  );

  final String uri;
  final String? text;
  final String? mimeType;

  @override
  JsonMap toJson() => {
    'type': 'resource',
    'resource': {
      'uri': uri,
      'text': text ?? '',
      if (mimeType != null) 'mimeType': mimeType,
    },
  };
}

/// A block type ShellX does not draw.
final class OtherBlock extends ContentBlock {
  const OtherBlock(this.type);

  final String? type;

  @override
  JsonMap toJson() => {'type': type ?? 'unknown'};
}

/// The text of [blocks]: text as it is, resource links as `@name`, other
/// blocks as nothing. Used for labels, never for logs.
String blockText(Iterable<ContentBlock> blocks) => blocks
    .map(
      (b) => switch (b) {
        TextBlock(:final text) => text,
        ResourceLinkBlock(:final name) => '@$name',
        _ => '',
      },
    )
    .join();
