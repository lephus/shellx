# L7 share links: end-to-end results (Task B9)

Harness: `scripts/shellx/share-e2e.mjs`, wrapped by `tests/test_shellx_share_e2e.py`
(lane `manual` in `tests/test-execution.toml`). Everything runs on loopback:

- `cmux-relay serve` (`cargo build -p cmux-relay`), HMAC secret from a 0600 temp file,
  issuer `shellx-relay`, `CMUX_RELAY_ALLOWED_ORIGINS=https://shellx.pro`.
- The Node API (`relay/src`) in process, rate limits off. It uses two hooks the API already
  has: `now` (shifted only for the POST of the expiry share) and `shareId` (see finding 1).
- The Swift `ShareHost` through the test-only executable `share-e2e-host`
  (`Packages/Shared/ShellXBrand/Sources/ShareE2EHost`). It has a scripted `ShareSource`
  (terminal `p1` 80x24 that echoes typed input, browser placeholder `b1`) and a ticket provider
  that calls `POST /v2/shares/:id/host-ticket` with a test desktop token.
- The viewer is `web/src/share/session.mjs` running in Node. It uses `ws` with
  `Origin: https://shellx.pro` (Node's global WebSocket cannot set Origin) and a fetch that
  adds the same Origin.

Debug traces: `SHARE_E2E_DEBUG=1 node scripts/shellx/share-e2e.mjs`.

## Run (Step 2) on 2026-10-21, `shellx/l7-b9` @ ec2de61a88 (`shellx/l7-share` 2c09dc931e merged)

`python3 tests/test_shellx_share_e2e.py`. API JSON log lines are omitted.

```
$ swift build --product share-e2e-host
Build of product 'share-e2e-host' complete! (0.24s)
cmux-relay 127.0.0.1:63706 (allowed origin https://shellx.pro), API http://127.0.0.1:63709

== origins
PASS origins: cmux-relay admits https://shellx.pro
PASS origins: cmux-relay refuses another Origin
PASS origins: cmux-relay admits a host with no Origin

== type share: welcome, replay, echo, revoke
PASS type: welcome perm=type with the scripted panes ([{"id":"p1","title":"zsh","kind":"terminal","cols":80,"rows":24},{"id":"b1","title":"Docs","kind":"browser","cols":0,"rows":0}])
PASS type: welcome expires_at_unix matches the API
PASS type: replay of p1 follows welcome
PASS type: host lists the viewer label
PASS type: typed "echo hi\r" comes back as output (33 ms)
PASS type: revoke -> viewer state revoked (bye revoked) within 1 s (7 ms)
PASS type: a new viewer of the revoked link gets revoked from the API

== view share: input dropped
PASS view: welcome perm=view, canType false
PASS view: the session sends no in frame
PASS view: a forged in frame is dropped by the host (dropped_input=1)
PASS view: viewer still live after the forged frame
PASS view: host quit -> viewer host_offline (bye host_quit)

== expiry: 15m share created on a shifted API clock so it expires in ~5 s
PASS expiry: share expires in under 6 s (4995 ms left)
PASS expiry: viewer state expired at expires_at (19 ms after expires_at)
PASS expiry: a new viewer gets expired from the API
PASS expiry: host stopped itself

== one-time (QR) share: first viewer binds, a second is refused, reconnect allowed
PASS one-time: first viewer live with perm=type
PASS one-time: a second browser gets used
PASS one-time: the same phone reconnects and types
PASS origins: every viewer ticket answered Access-Control-Allow-Origin https://shellx.pro (8 tickets)

share-e2e: 23 checks passed
PASS: share links end to end
```

Red and green for the viewer fix, with `node scripts/shellx/share-e2e.mjs --no-build` run 10 times each:
8/10 failed on 8f8951939f (`FAIL ... waiting for viewer state host_offline (now ended {"relay":"peer-disconnected"})`,
once on `expired`). 10/10 passed on ec2de61a88. `node --test web/tests/share.test.mjs` passed 44/44.

## Interop findings

1. **`access` cannot be computed before the share id exists (blocking for the app).**
   R4 sets `access = HKDF(secret, salt = share_id, ...)`, but `POST /v2/shares` requires `access` in
   its body and only returns the id in its response (`relay/src/v2/shares.ts`, create route:
   `ACCESS_RE.test(body.access)` before `c.get("shareId")()`). The desktop cannot derive a valid
   `access` without the id. The harness works around it with the API's `shareId` test hook,
   choosing the id before the POST. Possible fixes: the client proposes the id (409 on collision),
   or a second call sets `access` after creation, or the access salt does not depend on the id.
2. **Viewer lost `bye` to a racing relay error (fixed here, one line).** `web/src/share/session.mjs`
   circuit `onmessage` handled a text `error` (`peer-disconnected`) at once, while the `bye`
   that arrived before it was still in the async `inbound` decrypt chain. The viewer ended as
   `ended` instead of `revoked`, `expired` or `host_offline`. The fix waits on `inbound` first,
   as `onclose` already does (commit ec2de61a88).
3. **Minor: expiry rounding.** The API stores `expires_at` in ms but announces
   `floor(seconds)`. The host stops at the floored second, so for up to 999 ms the API still mints
   viewer tickets and a new viewer sees `host_offline` (relay `slot-offline`) instead of `expired`.
4. **Minor: socket identity.** `ShareHost.isCurrent` compares sockets with `as AnyObject ===`, but
   `ShareSocket` is not class-bound. A struct `ShareSocket` drops every frame without a sound.
   Production uses a class (`URLSessionShareSocket`); the harness wrapper is a class too.
   `protocol ShareSocket: AnyObject, Sendable` would rule out the mistake.

Not covered: A2 keepalive (`ka` after 60 s idle; relay idle close is 300 s). A minutes-long run
would be needed.

## Dogfood (Step 3)

Not done in this task (phone dogfood with a tagged app build is left to the controller/user).
