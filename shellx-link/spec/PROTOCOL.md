# ShellX Link protocol v1

ShellX Link lets a phone (client) answer agent prompts on a Mac or PC (host) through an
untrusted relay. This document and `spec/vectors/messages.json` are the source of truth for
every implementation (Swift, Rust, Kotlin). Key words MUST / MUST NOT / MAY are normative.

## 1. Transport

- The peers share a `cmux-relay` circuit using the `Single` framing. The relay forwards bytes
  and is not trusted.
- Every binary WebSocket message carries exactly one Noise message (handshake or transport).
  The two Link peers MUST NOT send each other text WebSocket messages. Text messages on the
  circuit are the relay's own control messages (`ping`, answered with `pong`, and `error`);
  they are not Link frames and are outside this protocol.
- A Noise transport message holds exactly one JSON frame (section 3). Frames are never split
  across, or batched into, Noise messages.

## 2. Handshake

- Pattern `Noise_XX_25519_ChaChaPoly_SHA256`, prologue the ASCII bytes `shellx-link/1`.
- The client is the Noise initiator, the host is the responder.
- The first 3 WebSocket messages are the handshake messages 1 (initiator), 2 (responder),
  3 (initiator). Everything after them is transport data.
- Handshake payloads MUST be empty in v1. An implementation MUST send empty payloads and
  MUST abort if it receives a non-empty one. Reason: the XX message-2 payload is encrypted
  only to the initiator's ephemeral key, so any initiator can read it before the responder
  has authenticated that initiator.
- A peer's static public key is an authenticated identity only after the handshake has
  completed successfully (message 3 processed by the responder, message 2 by the initiator).
  Before that, the key MUST NOT be used to look up, trust, display as verified, or remember
  a device.
- After the handshake the client sends `hello`; the host answers `welcome` (or `error`).

## 3. Frame

A frame is one UTF-8 JSON object:

```json
{"v":1,"t":"<type>", ...fields}
```

- `v` is the integer protocol version (1). `t` is the message type string.
- Field names are `snake_case`. Optional fields that have no value are omitted, never `null`.
- Receivers MUST ignore unknown fields. Senders MUST NOT rely on key order or whitespace.
- Integers are JSON numbers without fraction or exponent. `nonce` is a plain JSON number holding an
  unsigned 64-bit integer (0 to 18446744073709551615); implementations MUST parse it as an
  integer and MUST NOT parse it through a double. (It is not carried as a string.)
- `v` MUST be a JSON integer token. `1.0`, `1e0`, `"1"`, `true` and any other non-integer are
  `bad_json` (not `wrong_version`); only a well-formed integer other than 1 is `wrong_version`.
  `welcome.protocol_version` is always equal to the frame `v`, which is 1 in this version.
- Maximum frame size is 65 519 bytes: the UTF-8 byte length (not the character count) of the JSON text (65 535, the
  Noise maximum, minus the 16-byte tag). A frame of exactly 65 519 bytes is valid, 65 520 is not. A larger frame MUST be rejected on encode and on
  decode (`frame_too_large`). A sender whose content does not fit MUST shrink the content.
- Decoding order: (1) size check, (2) parse as an object with integer-token `v` and string `t`,
  else `bad_json`; (3) `v` != 1 gives `wrong_version`; (4) if `t` is unknown, the frame is
  `unknown` and is ignored (forward compatibility); (5) if `t` is known but a field is
  missing or has the wrong type or an unlisted enum value, `bad_json`. A known `t` never
  degrades to `unknown`.
- `unknown` is decode-only; an implementation MUST NOT be able to send it.

## 4. Messages

| `t` | Sender | When | Fields |
| --- | --- | --- | --- |
| `hello` | client | First frame after the handshake | `client_version` string, `device_name` string |
| `welcome` | host | Reply to an acceptable `hello` | `protocol_version` int, `host_version` string, `machine_name` string |
| `error` | either | A request cannot be honored | `code` string, `message` string (human readable) |
| `agent.snapshot.get` | client | After `welcome`, and whenever it wants a full resync | none |
| `agent.snapshot` | host | Reply to `agent.snapshot.get` | `revision` int, `pending` array of PendingItem |
| `agent.changed` | host | Whenever the pending set changes | `revision` int, `added` array of PendingItem, `resolved` array of request_id strings |
| `agent.reply` | client | The user decides on a pending item | `request_id` string, `mode` string |
| `agent.reply.result` | host | Reply to every `agent.reply` | `request_id` string, `outcome` string |
| `ping` | either | Keep-alive / latency probe | `nonce` uint64 |
| `pong` | either | Immediately after `ping`, echoing it | `nonce` uint64 (same value) |

Error codes in use: `protocol_mismatch`, `bad_request`. Others MAY be added; receivers treat
an unrecognized code as a generic error.

`revision` counts changes of the pending set. A host MUST raise it by exactly 1 with each
`agent.changed`, and an `agent.snapshot` at revision r includes every change up to r. A client
keeps the revision of the last snapshot or change it applied (its current revision), and for
each `agent.changed`:

- `revision` at or below the current one: it ignores the change, which it already has (for
  example from a snapshot taken after the change);
- `revision` exactly current + 1: it applies the change;
- `revision` above current + 1: it missed a change and MUST send `agent.snapshot.get`.

### PendingItem

| Field | Type | Notes |
| --- | --- | --- |
| `request_id` | string | Unique, stable id of the request |
| `kind` | string | `permission`, `question`, `exit_plan` |
| `agent` | string | `claude` in P1 |
| `workspace_id` | string | |
| `workspace_title` | string | |
| `tool_name` | string, optional | |
| `tool_input_preview` | string, optional | At most 8192 UTF-8 bytes (section 6) |
| `created_at_ms` | int64 | Unix time in milliseconds |

### Enums (exact strings)

- `mode`: `once`, `always`, `all`, `deny`.
- `outcome`: `delivered`, `already_handled`, `unknown`.

## 5. Rules

### Version

If the host receives a frame whose `v` is not 1, it sends
`{"v":1,"t":"error","code":"protocol_mismatch","message":"..."}` and then closes the
connection. The host's `error` frame always uses `v` 1.

### Idempotent `agent.reply`

A request is resolved at most once. For an `agent.reply`, the first rule that matches applies:

1. `request_id` never seen (or forgotten): the host answers `unknown`.
2. `request_id` no longer pending (resolved by this or another client or on the Mac, or
   expired): the host MUST NOT resolve it again and answers `already_handled`.
3. A request that is not a permission, or a `mode` this agent does not offer for the request:
   the host answers `unknown` and leaves the item as it was.
4. No agent is waiting for the request any more (the agent stopped waiting, it never waited
   because it sent the request without waiting, or the host restarted since the request
   arrived): nothing can take the decision. The host marks the
   item expired, not resolved, and answers `already_handled`.
5. Otherwise the host gives the waiting agent this decision and answers `delivered`, which
   means a waiting agent took this decision. When another client or the Mac took the agent's
   decision first, the host answers `already_handled` instead.

A host MUST answer the `agent.reply` messages for one `request_id` in the order they arrived.
Replies to different requests may be answered in any order.

Resending the same reply is therefore always safe. After `delivered` or `already_handled` the
item is no longer pending: in every case it leaves the pending set, and clients learn that
through an `agent.changed` that lists its `request_id` in `resolved` (or from a later
snapshot). The host does not order that change against the `agent.reply.result`: either may
arrive first.

## 6. Preview truncation and oversize frames

`tool_input_preview` is cut by the host to at most 8192 UTF-8 bytes. Every cut falls on a
Unicode scalar boundary: the result is valid UTF-8, never a split character. The client treats
the preview as display text only, not as the complete tool input.

Several items of 8 KiB previews can overflow the frame limit (eight already do). If an
`agent.snapshot` or `agent.changed` frame would exceed 65 519 bytes, the host shrinks the
previews in steps and re-encodes after each step, stopping at the first that fits:

1. every `tool_input_preview` truncated to at most 8192 bytes;
2. every `tool_input_preview` truncated to at most 1024 bytes;
3. `tool_input_preview` omitted on every item.

If the frame still does not fit after step 3, the host MUST NOT send it; it logs the failure
(a client recovers through `agent.snapshot.get`, which the host answers with the same rule).
Splitting one logical message into several frames is not defined in v1.

## 7. Error handling and session phases

Phases: after the handshake the session is *pre-hello*; it becomes *established* when the host
sends `welcome`.

| Phase | Client may send | Host may send |
| --- | --- | --- |
| pre-hello | `hello` only | `error` only |
| established | everything except `hello` | everything except `welcome` |

`ping`/`pong` are valid only when established. A `hello` or `welcome` received in the wrong
phase is a protocol violation, handled like any other unexpected frame below.

Rules:

- **Undecodable frame** (`bad_json` or `frame_too_large`): received by the host, it replies
  `error` with code `bad_request` and keeps the session. Received by the client, it drops the
  frame and logs it.
- **`wrong_version`**: the host sends `error` code `protocol_mismatch` and then closes the
  connection. A client that receives `error` `protocol_mismatch` closes the connection and tells
  the user to update the app.
- **First frame is not `hello`**: the host sends `error` code `bad_request` and then closes.
- **Unknown `t`**: ignored by both sides, session kept.
- A frame that decodes but is not allowed in the current phase or direction (for example a
  client sending `welcome`) is ignored; the host MAY answer `error` `bad_request`.

## 8. Golden vectors

`spec/vectors/messages.json` holds:

- `vectors`: `{name, message, json}`. Decoding `json` MUST give `message`; encoding `message`
  MUST give JSON semantically equal to `json`.
- `decode_only`: decoding `json` MUST give `message` (unknown type, unknown fields).
- `decode_errors`: decoding `json` (or the raw text `json_text`, used where the exact number or
  string token matters) MUST fail with the named error (`wrong_version`, `bad_json`, `frame_too_large`).
- `boundary_frames`: generated frames. Frame text = `prefix` + filler + `suffix`, where filler is
  each `{text, count}` repeated and concatenated. Entries check exactly 65 519 bytes (accepted),
  65 520 bytes (`frame_too_large`) and multi-byte content whose byte count exceeds the limit while
  its character count does not. Encoding the `error` message with that filler as `message` must
  succeed or fail the same way.

`message.case` names the message; the other `message` keys use the JSON field names. All 11 cases:

| `message.case` | Wire `t` | Other keys |
| --- | --- | --- |
| `hello` | `hello` | `client_version`, `device_name` |
| `welcome` | `welcome` | `protocol_version`, `host_version`, `machine_name` |
| `error` | `error` | `code`, `message` |
| `snapshot_get` | `agent.snapshot.get` | none |
| `snapshot` | `agent.snapshot` | `revision`, `pending` |
| `changed` | `agent.changed` | `revision`, `added`, `resolved` |
| `reply` | `agent.reply` | `request_id`, `mode` |
| `reply_result` | `agent.reply.result` | `request_id`, `outcome` |
| `ping` | `ping` | `nonce` |
| `pong` | `pong` | `nonce` |
| `unknown` | any unrecognized `t` | `type` (the `t` value); decode-only |
