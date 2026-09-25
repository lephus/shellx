import 'package:shellx_mobile/shared/shared.dart';

/// The `…` of "Lần cuối online: …" (spec §9.2 #2, §12) in the design's wording:
/// "vừa xong", "5 phút trước", "hôm nay, 09:12", "hôm qua, 18:05", "23/9, 18:05".
String formatLastSeen(S strings, DateTime? lastSeen, DateTime now) {
  if (lastSeen == null) return strings.lastSeenUnknown;
  final local = lastSeen.toLocal();
  final elapsed = now.difference(local);
  if (elapsed.inMinutes < 1) return strings.lastSeenJustNow;
  if (elapsed.inHours < 1) return strings.lastSeenMinutes(elapsed.inMinutes);
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return strings.lastSeenToday(time);
  if (day == today.subtract(const Duration(days: 1))) return strings.lastSeenYesterday(time);
  return strings.lastSeenDate(local.day, local.month, time);
}
