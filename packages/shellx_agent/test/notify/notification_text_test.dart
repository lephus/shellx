import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

CompletedCommand _cmd(String? line, int code, Duration d) =>
    CompletedCommand(commandLine: line, exitCode: code, duration: d);

void main() {
  final vi = NotificationText('vi_VN');
  final en = NotificationText('en-US');

  test('Vietnamese for vi*, English otherwise', () {
    expect(vi.vietnamese, isTrue);
    expect(NotificationText('VI').vietnamese, isTrue);
    expect(en.vietnamese, isFalse);
    expect(NotificationText('').vietnamese, isFalse);
    expect(NotificationText('fr_FR').vietnamese, isFalse);
  });

  test('durations', () {
    expect(vi.duration(const Duration(seconds: 45)), '45 giây');
    expect(
      vi.duration(const Duration(minutes: 3, seconds: 12)),
      '3 phút 12 giây',
    );
    expect(
      vi.duration(const Duration(hours: 1, minutes: 4, seconds: 9)),
      '1 giờ 4 phút',
    );
    expect(vi.duration(const Duration(minutes: 3)), '3 phút');
    expect(vi.duration(const Duration(hours: 2)), '2 giờ');
    expect(vi.duration(const Duration(milliseconds: 999)), '0 giây');
    expect(en.duration(const Duration(seconds: 45)), '45 s');
    expect(en.duration(const Duration(minutes: 3, seconds: 12)), '3 min 12 s');
    expect(en.duration(const Duration(hours: 1, minutes: 4)), '1 h 4 min');
    expect(en.duration(const Duration(seconds: -3)), '0 s');
  });

  test('command bodies (spec §4.2)', () {
    expect(
      vi.commandBody(
        _cmd('npm test', 0, const Duration(minutes: 3, seconds: 12)),
      ),
      '✓ npm test · 3 phút 12 giây',
    );
    expect(
      vi.commandBody(_cmd('make', 1, const Duration(seconds: 45))),
      '✗ make · mã 1 · 45 giây',
    );
    expect(
      en.commandBody(_cmd('make', 1, const Duration(seconds: 45))),
      '✗ make · exit 1 · 45 s',
    );
    expect(vi.commandBody(_cmd(null, 0, Duration.zero)), '✓ Lệnh · 0 giây');
    expect(en.commandBody(_cmd('  ', 0, Duration.zero)), '✓ Command · 0 s');
    expect(en.commandBody(_cmd('a\nb\t c', 0, Duration.zero)), '✓ a b c · 0 s');
  });

  test('titles: machine · session', () {
    expect(vi.title('MacBook', vi.shellSession(2)), 'MacBook · Phiên 2');
    expect(en.title('MacBook', en.shellSession(2)), 'MacBook · Session 2');
    expect(
      en.title('MacBook', en.desktopSession('Terminal', 'npm run dev')),
      'MacBook · Terminal — npm run dev',
    );
    expect(en.desktopSession('iTerm2', ''), 'iTerm2');
    expect(en.title('', 'Session 1'), 'Session 1');
    expect(en.title('Mac', ''), 'Mac');
    expect(en.title('', ''), 'ShellX');
  });
}
