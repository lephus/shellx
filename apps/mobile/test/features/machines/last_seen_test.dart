import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/last_seen.dart';
import 'package:shellx_mobile/shared/shared.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('the design wording in Vietnamese', () async {
    final vi = await S.load(const Locale('vi'));
    expect(formatLastSeen(vi, null, now), 'không rõ');
    expect(formatLastSeen(vi, now.subtract(const Duration(seconds: 30)), now), 'vừa xong');
    expect(formatLastSeen(vi, now.subtract(const Duration(minutes: 5)), now), '5 phút trước');
    expect(formatLastSeen(vi, DateTime(2026, 9, 25, 9, 12), now), 'hôm nay, 09:12');
    expect(formatLastSeen(vi, DateTime(2026, 9, 24, 18, 5), now), 'hôm qua, 18:05');
    expect(formatLastSeen(vi, DateTime(2026, 9, 23, 18, 5), now), '23/9, 18:05');
  });

  test('English; a timestamp in the future (clock skew) reads as "just now"', () async {
    final en = await S.load(const Locale('en'));
    expect(formatLastSeen(en, now.subtract(const Duration(minutes: 1)), now), '1 minute ago');
    expect(formatLastSeen(en, DateTime(2026, 9, 24, 18, 5), now), 'yesterday, 18:05');
    expect(formatLastSeen(en, DateTime(2026, 9, 23, 18, 5), now), '9/23, 18:05');
    expect(formatLastSeen(en, now.add(const Duration(minutes: 3)), now), 'just now');
  });
}
