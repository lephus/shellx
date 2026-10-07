import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

String? local(ReportedCwd? cwd) => cwd is LocalCwd ? cwd.path : null;

void main() {
  ReportedCwd? mac(String url) =>
      parseCwdUrl(url, windows: false, localHostName: 'Richards-MBP.local');
  ReportedCwd? win(String url) =>
      parseCwdUrl(url, windows: true, localHostName: 'DESKTOP-1');

  group('POSIX', () {
    test('empty host, localhost and this machine are local', () {
      expect(local(mac('file:///Users/r')), '/Users/r');
      expect(local(mac('file://localhost/Users/r')), '/Users/r');
      expect(local(mac('file://richards-mbp/Users/r')), '/Users/r');
      expect(local(mac('file://Richards-MBP.local/Users/r')), '/Users/r');
    });

    test('percent-encoding is UTF-8: spaces, Vietnamese, % itself', () {
      expect(
        local(mac('file:///Users/r/T%C3%A0i%20li%E1%BB%87u/100%25')),
        '/Users/r/Tài liệu/100%',
      );
      // Raw non-ASCII (a hook that did not encode) is accepted as is.
      expect(local(mac('file:///Users/r/ư')), '/Users/r/ư');
    });

    test('another host is remote (D2): the caller forgets the directory', () {
      expect(mac('file://build-server/home/r'), isA<RemoteCwd>());
    });

    test('malformed URLs are null (ignored)', () {
      expect(mac('http:///Users/r'), isNull);
      expect(mac('file://'), isNull);
      expect(mac('file:///bad%zz'), isNull);
      expect(mac('file:///trunc%4'), isNull);
      expect(mac('file:///bad%FF%FE'), isNull); // not UTF-8
      expect(mac('file:///nul%00x'), isNull);
    });
  });

  group('Windows', () {
    test('a drive path becomes C:\\…', () {
      expect(local(win('file:///C:/Users/r/a%20b')), r'C:\Users\r\a b');
      expect(local(win('file:///d:')), r'D:\');
      expect(local(win('file://localhost/C:/x')), r'C:\x');
    });

    test('a server host is a UNC path, not remote', () {
      expect(local(win('file://nas/share/src')), r'\\nas\share\src');
    });

    test('a local URL without a drive is ignored', () {
      expect(win('file:///home/r'), isNull);
    });
  });

  test('parseRemoteCwdPath: any host, decoded path (A8 D14)', () {
    expect(
      parseRemoteCwdPath('file://devbox/home/me/work%20x'),
      '/home/me/work x',
    );
    expect(parseRemoteCwdPath('file:///srv'), '/srv');
    expect(parseRemoteCwdPath('file://h/%E1%BA%BF'), '/ế');
    expect(parseRemoteCwdPath('file://h/a%00b'), isNull);
    expect(parseRemoteCwdPath('file://h/a%0Ab'), isNull);
    expect(parseRemoteCwdPath('file://h/a%C2%85b'), isNull);
    expect(parseRemoteCwdPath('file://h/%ZZ'), isNull);
    expect(parseRemoteCwdPath('http://h/x'), isNull);
    expect(parseRemoteCwdPath('file://h'), isNull);
    expect(parseRemoteCwdPath('file://h/${'a' * 4100}'), isNull);
  });
}
