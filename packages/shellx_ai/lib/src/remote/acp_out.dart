import 'package:shellx_acp/shellx_acp.dart';

/// [request] back in the shape of `elicitation/create` params, so the phone
/// reads it with `ElicitationRequest.fromJson` and checks answers with the
/// same `accepts` as the desktop (V2-2 D7). Session and request ids are
/// left out: the desktop answers, not the phone.
Map<String, Object?> elicitationToJson(ElicitationRequest request) =>
    switch (request) {
      ElicitationForm(
        :final message,
        :final title,
        :final description,
        :final fields,
      ) =>
        {
          'mode': 'form',
          'message': message,
          'requestedSchema': {
            'type': 'object',
            'title': ?title,
            'description': ?description,
            'properties': {for (final f in fields) f.key: _field(f)},
            'required': [
              for (final f in fields)
                if (f.required) f.key,
            ],
          },
        },
      ElicitationUrl(:final message, :final elicitationId, :final url) => {
        'mode': 'url',
        'message': message,
        'elicitationId': elicitationId,
        'url': url,
      },
      ElicitationOther(:final message, :final mode) => {
        'mode': ?mode,
        'message': message,
      },
    };

Map<String, Object?> _field(ElicitField f) {
  final common = {
    if (f.title != null) 'title': f.title,
    if (f.description != null) 'description': f.description,
  };
  List<Map<String, Object?>> titled(List<ElicitOption> options) => [
    for (final o in options) {'const': o.value, 'title': o.title},
  ];
  return switch (f) {
    ElicitTextField(
      :final minLength,
      :final maxLength,
      :final format,
      :final defaultValue,
    ) =>
      {
        'type': 'string',
        ...common,
        'minLength': ?minLength,
        'maxLength': ?maxLength,
        'format': ?format,
        'default': ?defaultValue,
      },
    ElicitNumberField(
      :final integer,
      :final minimum,
      :final maximum,
      :final defaultValue,
    ) =>
      {
        'type': integer ? 'integer' : 'number',
        ...common,
        'minimum': ?minimum,
        'maximum': ?maximum,
        'default': ?defaultValue,
      },
    ElicitBoolField(:final defaultValue) => {
      'type': 'boolean',
      ...common,
      'default': ?defaultValue,
    },
    ElicitChoiceField(:final options, :final defaultValue) => {
      'type': 'string',
      ...common,
      'oneOf': titled(options),
      'default': ?defaultValue,
    },
    ElicitMultiChoiceField(
      :final options,
      :final minItems,
      :final maxItems,
      :final defaultValue,
    ) =>
      {
        'type': 'array',
        ...common,
        'items': {'anyOf': titled(options)},
        'minItems': ?minItems,
        'maxItems': ?maxItems,
        'default': ?defaultValue,
      },
    ElicitUnsupportedField(:final type) => {'type': ?type, ...common},
  };
}
