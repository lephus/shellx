# A1 desktop terminal — overnight ledger (user granted full authority 2026-10-06)

Ruling: Q2 daemon → A1 keeps sessions in the existing agent process behind LocalSessions; daemon split moves to A5 — flutter_pty is a Flutter plugin, a pure-Dart daemon cannot use it overnight — cost if wrong: native crash/app update still kills shells until A5.
Ruling: accept every design-doc recommendation (F6 focus cycling, middle-click close, yellow eye while phone drives, ⌘W on empty state hides window, macOS transparent title bar layout, floating driver strip, exit text in terminal) — they serve "dễ sử dụng nhất" — cost if wrong: small UI rework.
Ruling: fix confirmSignOutBody / confirmRemoteOffBody to say shells keep running (spec D7).
Ruling: mobile contrast follow-ups (--t-dim text 4.3:1, white on #0097A8 3.5:1) scheduled as a mobile UI pass after A1 (user asked both apps be precise and easy to use) — cost if wrong: none.
Note: no skill named "claude-design" exists in this session; used design:design-system + design:ux-copy (design doc), design:design-critique + design:accessibility-review planned after build.
