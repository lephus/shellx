import 'package:intl/intl.dart';

/// "512 KB", "1.2 MB": for the confirmation of a very large paste (A10
/// D13). Powers of 1024, the decimal mark of [locale].
String formatByteSize(int bytes, {String? locale}) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).ceil().clamp(1, 1023)} KB';
  }
  final mb = NumberFormat('#,##0.0', locale).format(bytes / (1024 * 1024));
  return '$mb MB';
}
