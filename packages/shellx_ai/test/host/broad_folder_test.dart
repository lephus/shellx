import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  group('macOS / Linux', () {
    bool broad(String f, {String? home = '/Users/phu'}) =>
        isBroadFolder(f, home: home, isWindows: false);

    test('the root, the home folder and the folders above it are broad', () {
      expect(broad('/'), isTrue);
      expect(broad('/Users'), isTrue);
      expect(broad('/Users/phu'), isTrue);
      expect(broad('/Users/phu/'), isTrue);
      expect(broad('/Users/phu/./'), isTrue);
    });

    test('a project inside home, or a folder beside it, is not', () {
      expect(broad('/Users/phu/code/app'), isFalse);
      expect(broad('/Users/phu/Desktop'), isFalse);
      expect(broad('/Users/phuong'), isFalse);
      expect(broad('/opt/work'), isFalse);
      expect(broad('/Volumes/Disk/src'), isFalse);
    });

    test(
      'no home: only the root counts; relative or empty input is not broad',
      () {
        expect(broad('/', home: null), isTrue);
        expect(broad('/Users/phu', home: null), isFalse);
        expect(broad('/Users/phu', home: 'relative/home'), isFalse);
        expect(broad(''), isFalse);
        expect(broad('code/app'), isFalse);
      },
    );
  });

  group('Windows', () {
    bool broad(String f, {String? home = r'C:\Users\Phu'}) =>
        isBroadFolder(f, home: home, isWindows: true);

    test(
      'drive roots, the profile folder and the folders above it are broad',
      () {
        expect(broad(r'C:\'), isTrue);
        expect(broad(r'D:\'), isTrue);
        expect(broad(r'c:\users'), isTrue);
        expect(broad(r'C:\Users\phu'), isTrue);
        expect(broad(r'C:\Users\Phu\'), isTrue);
        expect(broad(r'\\server\share'), isTrue);
      },
    );

    test('a project inside the profile or on another drive is not', () {
      expect(broad(r'C:\Users\Phu\source\app'), isFalse);
      expect(broad(r'D:\work\app'), isFalse);
      expect(broad(r'C:\Users\Phuong'), isFalse);
      expect(broad(r'\\server\share\app'), isFalse);
    });
  });
}
