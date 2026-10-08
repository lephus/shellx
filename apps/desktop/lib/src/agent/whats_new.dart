import 'dart:convert';

/// A11 D23: the release notes bundled with the app
/// (`assets/whats_new.json`): `{ "1.2.0": { "en": [...], "vi": [...] } }`,
/// at most [maxLines] lines per language. Read from the asset only, never
/// from the network.
final class WhatsNew {
  const WhatsNew._(this._byVersion);

  /// Nothing to tell.
  static const WhatsNew empty = WhatsNew._({});

  static const int maxLines = 5;

  final Map<String, Map<String, List<String>>> _byVersion;

  /// Garbage (not JSON, not an object, a wrong shape) is an empty file:
  /// "what is new" is a courtesy and must never throw at startup.
  factory WhatsNew.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return empty;
    }
    if (decoded is! Map<String, Object?>) return empty;
    final out = <String, Map<String, List<String>>>{};
    for (final MapEntry(key: version, value: langs) in decoded.entries) {
      if (langs is! Map<String, Object?>) continue;
      final byLang = <String, List<String>>{};
      for (final MapEntry(key: lang, value: lines) in langs.entries) {
        if (lines is! List<Object?>) continue;
        final clean = [
          for (final l in lines)
            if (l is String && l.trim().isNotEmpty) l.trim(),
        ];
        if (clean.isNotEmpty) byLang[lang] = clean.take(maxLines).toList();
      }
      if (byLang.isNotEmpty) out[version] = byLang;
    }
    return WhatsNew._(out);
  }

  /// The lines for [version] (the build after `+` is ignored) in [locale]'s
  /// language, English when that language has none; null when the release
  /// has no notes.
  List<String>? notes(String version, String locale) {
    final langs = _byVersion[releaseOf(version)];
    if (langs == null) return null;
    return langs[locale] ?? langs['en'];
  }
}

/// `1.2.0+7` -> `1.2.0`: releases are compared without the build number.
String releaseOf(String version) => version.split('+').first.trim();
