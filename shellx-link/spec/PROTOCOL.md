# ShellX Link protocol v1

ShellX Link lets a phone (client) answer agent prompts on a Mac or PC (host) through an
untrusted relay. This document and `spec/vectors/messages.json` are the source of truth for
every implementation (Swift, Rust, Kotlin). Key words MUST / MUST NOT / MAY are normative.

## 1. Transport

- The peers share a `cmux-relay` circuit using the `Single` framing. The relay forwards bytes
  and is not trusted.
- Every binary WebSocket message carries exactly one Noise message (handshake or transport).
  Text WebSocket messages MUST NOT be used.
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
- Integers are JSON numbers without fraction or exponent. `nonce` is an unsigned 64-bit
  integer (0 to 18446744073709551615); implementations MUST NOT parse it through a double.
- Maximum frame size is 65 519 bytes: the UTF-8 byte length of the JSON text (65 535, the
  Noise maximum, minus the 16-byte tag). A larger frame MUST be rejected on encode and on
  decode (`frameTooLarge`). A sender whose content does not fit MUST shrink the content.
- Decoding order: (1) size check, (2) parse as an object with integer `v` and string `t`,
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

`revision` increases by at least 1 on every change of the pending set. A client applying
`agent.changed` whose `revision` is not exactly the previous revision + 1 MUST send
`agent.snapshot.get`.

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

A request is resolved at most once. For an `agent.reply`:

- `request_id` pending: the host resolves it and answers `delivered`.
- `request_id` already resolved (by this or another client, or on the Mac): the host MUST NOT
  resolve it again and answers `already_handled`.
- `request_id` never seen (or forgotten): the host answers `unknown`.

Resending the same reply is therefore always safe. After `delivered` or `already_handled`
the item is no longer pending, which clients also learn through `agent.changed`.

## 6. Preview truncation

`tool_input_preview` is cut by the host to at most 8192 UTF-8 bytes. The cut falls on a
Unicode scalar boundary: the result is valid UTF-8, never a split character. The client treats
the preview as display text only, not as the complete tool input.

## 7. Golden vectors

`spec/vectors/messages.json` holds:

- `vectors`: `{name, message, json}`. Decoding `json` MUST give `message`; encoding `message`
  MUST give JSON semantically equal to `json`.
- `decode_only`: decoding `json` MUST give `message` (unknown type, unknown fields).
- `decode_errors`: decoding `json` MUST fail with the named error (`wrong_version`, `bad_json`).

`message.case` names the message (`snapshot_get`, `reply_result`, ... in snake_case); the other
`message` keys use the JSON field names.
