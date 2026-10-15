import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/tools/tool_navigation.dart';

NavigationVerdict top(String url) =>
    toolNavigation(Uri.tryParse(url), mainFrame: true, newWindow: false);
NavigationVerdict window(String url) =>
    toolNavigation(Uri.tryParse(url), mainFrame: true, newWindow: true);
NavigationVerdict frame(String url) =>
    toolNavigation(Uri.tryParse(url), mainFrame: false, newWindow: false);

void main() {
  const allow = NavigationVerdict.allow;
  const outside = NavigationVerdict.outside;
  const block = NavigationVerdict.block;

  test('the top frame: any http/https page, about:blank; mail and phone '
      'outside; anything else blocked (D9, Review Focus 5)', () {
    expect(top('http://localhost:5173/x'), allow);
    expect(top('https://sso.example.com/login'), allow, reason: 'SSO');
    expect(top('about:blank'), allow);
    expect(top('mailto:a@b.c'), outside);
    expect(top('tel:+84123'), outside);
    for (final url in [
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,hi',
      'blob:http://localhost/1',
      'shellx-test://x',
      'about:srcdoc',
      'http://',
    ]) {
      expect(top(url), block, reason: url);
    }
    expect(toolNavigation(null, mainFrame: true, newWindow: false), block);
  });

  test('a new window never opens in the tool: web, mail and phone go '
      'outside, the rest nowhere (D9)', () {
    expect(window('https://docs.example.com/'), outside);
    expect(window('http://localhost:5173/other'), outside);
    expect(window('mailto:a@b.c'), outside);
    expect(window('javascript:alert(1)'), block);
    expect(window('file:///x'), block);
  });

  test('frames of the page load web, about, data and blob content; the '
      'rest is blocked', () {
    expect(frame('https://embed.example.com/'), allow);
    expect(frame('about:srcdoc'), allow);
    expect(frame('data:text/html,hi'), allow);
    expect(frame('blob:http://localhost/1'), allow);
    expect(frame('mailto:a@b.c'), block);
    expect(frame('file:///x'), block);
  });
}
