import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';

const _served = {'http://localhost:5173', 'http://localhost:8000'};

ToolNavigation _top(String url) => toolNavigation(url, mainFrame: true, origins: _served);

/// V2-4 E12: where the tool page's web view may go.
void main() {
  test('the pages this phone serves, and about:blank', () {
    expect(_top('http://localhost:5173/'), isA<ToolGo>());
    expect(_top('http://localhost:8000/api?x=1'), isA<ToolGo>());
    expect(_top('about:blank'), isA<ToolGo>());
  });

  test('another loopback spelling of a served port goes to localhost (E2)', () {
    final go = _top('http://127.0.0.1:5173/login?next=%2F') as ToolGoInstead;
    expect(go.url.toString(), 'http://localhost:5173/login?next=%2F');
    expect((_top('http://[::1]:8000/') as ToolGoInstead).url.toString(), 'http://localhost:8000/');
  });

  test('a local port not served: stopped and named (E4)', () {
    expect((_top('http://localhost:9000/') as ToolOtherLocal).port, 9000);
    expect((_top('http://127.0.0.1:80/') as ToolOtherLocal).port, 80);
  });

  test('another site asks first; https to localhost is another site', () {
    expect((_top('https://accounts.example.com/sso') as ToolAskExternal).url.host, 'accounts.example.com');
    expect(_top('http://192.168.1.9:5173/'), isA<ToolAskExternal>());
    expect(_top('https://localhost:5173/'), isA<ToolAskExternal>());
  });

  test('other schemes at the top are stopped; frames inside the page go on', () {
    for (final url in ['javascript:alert(1)', 'file:///etc/hosts', 'intent://x#Intent;end', 'data:text/html,hi', '']) {
      expect(_top(url), isA<ToolBlock>(), reason: url);
    }
    expect(toolNavigation('data:text/html,hi', mainFrame: false, origins: _served), isA<ToolGo>());
  });
}
