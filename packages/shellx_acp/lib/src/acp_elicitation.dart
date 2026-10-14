import 'acp_json.dart';
import 'json_rpc.dart';

/// The agent asks the user something (`elicitation/create`, spec D22).
sealed class ElicitationRequest with Redacted {
  const ElicitationRequest({
    required this.message,
    this.sessionId,
    this.toolCallId,
    this.requestId,
  });

  static ElicitationRequest fromJson(JsonMap j) {
    final message = readString(j, 'message') ?? '';
    final sessionId = readString(j, 'sessionId');
    final toolCallId = readString(j, 'toolCallId');
    final requestId = j['requestId'];
    switch (readString(j, 'mode')) {
      case 'form':
        final schema =
            readMap(j, 'requestedSchema') ?? const <String, Object?>{};
        final required = readStrings(schema, 'required').toSet();
        final props =
            readMap(schema, 'properties') ?? const <String, Object?>{};
        return ElicitationForm(
          message: message,
          sessionId: sessionId,
          toolCallId: toolCallId,
          requestId: requestId,
          title: readString(schema, 'title'),
          description: readString(schema, 'description'),
          fields: [
            for (final e in props.entries)
              if (e.value case final JsonMap p)
                ElicitField.fromJson(
                  e.key,
                  p,
                  required: required.contains(e.key),
                ),
          ],
        );
      case 'url':
        final id = readString(j, 'elicitationId');
        final url = readString(j, 'url');
        if (id != null && url != null) {
          return ElicitationUrl(
            message: message,
            sessionId: sessionId,
            toolCallId: toolCallId,
            requestId: requestId,
            elicitationId: id,
            url: url,
          );
        }
        return ElicitationOther(
          message: message,
          sessionId: sessionId,
          toolCallId: toolCallId,
          requestId: requestId,
          mode: 'url',
        );
      case final mode:
        return ElicitationOther(
          message: message,
          sessionId: sessionId,
          toolCallId: toolCallId,
          requestId: requestId,
          mode: mode,
        );
    }
  }

  final String message;
  final String? sessionId;
  final String? toolCallId;

  /// Set when the question belongs to a request (e.g. `session/new` asking
  /// to sign in to an MCP server) instead of a session.
  final Object? requestId;
}

final class ElicitationForm extends ElicitationRequest {
  const ElicitationForm({
    required super.message,
    super.sessionId,
    super.toolCallId,
    super.requestId,
    this.title,
    this.description,
    this.fields = const [],
  });

  final String? title;
  final String? description;
  final List<ElicitField> fields;

  /// False when a field uses a type ShellX cannot show; then the card says
  /// so and the answer is `decline` (spec D22).
  bool get supported => fields.every((f) => f is! ElicitUnsupportedField);

  /// [content] answers every required field with an accepted value and has
  /// no key the form did not ask for.
  bool accepts(Map<String, Object?> content) {
    final keys = {for (final f in fields) f.key};
    if (content.keys.any((k) => !keys.contains(k))) return false;
    for (final f in fields) {
      final v = content[f.key];
      if (v == null) {
        if (f.required) return false;
      } else if (!f.accepts(v)) {
        return false;
      }
    }
    return true;
  }
}

final class ElicitationUrl extends ElicitationRequest {
  const ElicitationUrl({
    required super.message,
    super.sessionId,
    super.toolCallId,
    super.requestId,
    required this.elicitationId,
    required this.url,
  });

  final String elicitationId;
  final String url;

  /// Only http and https URLs with a host may be opened, after a click
  /// (spec D22, §5).
  bool get isWebUrl {
    final u = Uri.tryParse(url);
    return u != null &&
        (u.scheme == 'http' || u.scheme == 'https') &&
        u.host.isNotEmpty;
  }
}

/// A mode this version does not know; answered `decline`.
final class ElicitationOther extends ElicitationRequest {
  const ElicitationOther({
    required super.message,
    super.sessionId,
    super.toolCallId,
    super.requestId,
    this.mode,
  });

  final String? mode;
}

final class ElicitOption with Redacted {
  const ElicitOption(this.value, this.title);

  final String value;
  final String title;
}

/// One form field (string, number, boolean, single or multiple choice).
sealed class ElicitField with Redacted {
  const ElicitField({
    required this.key,
    required this.required,
    this.title,
    this.description,
  });

  static ElicitField fromJson(String key, JsonMap j, {required bool required}) {
    final title = readString(j, 'title');
    final description = readString(j, 'description');
    List<ElicitOption> titled(Iterable<JsonMap> items) => [
      for (final o in items)
        if (readString(o, 'const') case final String v)
          ElicitOption(v, readString(o, 'title') ?? v),
    ];
    switch (readString(j, 'type')) {
      case 'string':
        if (readList(j, 'oneOf') != null || readList(j, 'enum') != null) {
          final oneOf = titled(readMaps(j, 'oneOf'));
          return ElicitChoiceField(
            key: key,
            required: required,
            title: title,
            description: description,
            options: oneOf.isNotEmpty
                ? oneOf
                : [for (final v in readStrings(j, 'enum')) ElicitOption(v, v)],
            defaultValue: readString(j, 'default'),
          );
        }
        return ElicitTextField(
          key: key,
          required: required,
          title: title,
          description: description,
          minLength: readInt(j, 'minLength'),
          maxLength: readInt(j, 'maxLength'),
          format: readString(j, 'format'),
          defaultValue: readString(j, 'default'),
        );
      case final t && ('number' || 'integer'):
        return ElicitNumberField(
          key: key,
          required: required,
          title: title,
          description: description,
          integer: t == 'integer',
          minimum: readNum(j, 'minimum'),
          maximum: readNum(j, 'maximum'),
          defaultValue: readNum(j, 'default'),
        );
      case 'boolean':
        return ElicitBoolField(
          key: key,
          required: required,
          title: title,
          description: description,
          defaultValue: readBool(j, 'default'),
        );
      case 'array':
        final items = readMap(j, 'items') ?? const <String, Object?>{};
        final anyOf = titled(readMaps(items, 'anyOf'));
        final options = anyOf.isNotEmpty
            ? anyOf
            : [for (final v in readStrings(items, 'enum')) ElicitOption(v, v)];
        if (options.isEmpty) {
          return ElicitUnsupportedField(
            key: key,
            required: required,
            title: title,
            description: description,
            type: 'array',
          );
        }
        return ElicitMultiChoiceField(
          key: key,
          required: required,
          title: title,
          description: description,
          options: options,
          minItems: readInt(j, 'minItems'),
          maxItems: readInt(j, 'maxItems'),
          defaultValue: readList(j, 'default') == null
              ? null
              : readStrings(j, 'default'),
        );
      case final type:
        return ElicitUnsupportedField(
          key: key,
          required: required,
          title: title,
          description: description,
          type: type,
        );
    }
  }

  final String key;
  final bool required;
  final String? title;
  final String? description;

  /// [value] is a valid answer for this field.
  bool accepts(Object value);
}

final class ElicitTextField extends ElicitField {
  const ElicitTextField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    this.minLength,
    this.maxLength,
    this.format,
    this.defaultValue,
  });

  final int? minLength;
  final int? maxLength;

  /// `email`, `uri`, `date` or `date-time`: a keyboard hint only.
  final String? format;
  final String? defaultValue;

  @override
  bool accepts(Object value) =>
      value is String &&
      (minLength == null || value.length >= minLength!) &&
      (maxLength == null || value.length <= maxLength!);
}

final class ElicitNumberField extends ElicitField {
  const ElicitNumberField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    required this.integer,
    this.minimum,
    this.maximum,
    this.defaultValue,
  });

  final bool integer;
  final num? minimum;
  final num? maximum;
  final num? defaultValue;

  @override
  bool accepts(Object value) =>
      value is num &&
      value.isFinite &&
      (!integer || value is int) &&
      (minimum == null || value >= minimum!) &&
      (maximum == null || value <= maximum!);
}

final class ElicitBoolField extends ElicitField {
  const ElicitBoolField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    this.defaultValue,
  });

  final bool? defaultValue;

  @override
  bool accepts(Object value) => value is bool;
}

final class ElicitChoiceField extends ElicitField {
  const ElicitChoiceField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    required this.options,
    this.defaultValue,
  });

  final List<ElicitOption> options;
  final String? defaultValue;

  @override
  bool accepts(Object value) =>
      value is String && options.any((o) => o.value == value);
}

final class ElicitMultiChoiceField extends ElicitField {
  const ElicitMultiChoiceField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    required this.options,
    this.minItems,
    this.maxItems,
    this.defaultValue,
  });

  final List<ElicitOption> options;
  final int? minItems;
  final int? maxItems;
  final List<String>? defaultValue;

  @override
  bool accepts(Object value) =>
      value is List &&
      value.every((v) => v is String && options.any((o) => o.value == v)) &&
      value.toSet().length == value.length &&
      (minItems == null || value.length >= minItems!) &&
      (maxItems == null || value.length <= maxItems!);
}

/// A field type ShellX cannot show (spec D22).
final class ElicitUnsupportedField extends ElicitField {
  const ElicitUnsupportedField({
    required super.key,
    required super.required,
    super.title,
    super.description,
    this.type,
  });

  final String? type;

  @override
  bool accepts(Object value) => false;
}

/// The user's answer to an elicitation.
sealed class ElicitationResponse with Redacted {
  const ElicitationResponse();

  JsonMap toJson();
}

final class ElicitAccept extends ElicitationResponse {
  const ElicitAccept([this.content]);

  /// The form values; null for a URL question.
  final Map<String, Object>? content;

  @override
  JsonMap toJson() => {
    'action': 'accept',
    if (content != null) 'content': content,
  };
}

final class ElicitDecline extends ElicitationResponse {
  const ElicitDecline();

  @override
  JsonMap toJson() => {'action': 'decline'};
}

final class ElicitCancel extends ElicitationResponse {
  const ElicitCancel();

  @override
  JsonMap toJson() => {'action': 'cancel'};
}
