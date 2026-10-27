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
  missing or has the wrong type, `bad_json` (an unlisted enum value is not an error, see
  Extension). A known `t` never degrades to `unknown`.
- `unknown` is decode-only; an implementation MUST NOT be able to send it.

### Extension

- Every string enum field is an open enum: `kind` (of a PendingItem, of a decision and of a ChatEntry), `mode`,
  `outcome`, `state` (of an AgentSession), `role` (of a ChatEntry), and the enum fields later versions add. A value this version does not know still
  decodes (an implementation keeps the raw string, for example as `.other(raw)`); it is never
  `bad_json`.
- A sender MAY add an optional field at any time; receivers ignore fields they do not know.
- Adding a required field, or changing the meaning of a field, requires raising `v`.
- `v` stays 1 in P2: the P2 changes revise v1 before its first release, because no P1 build has
  left the spike.

### Call ids

Every request that expects exactly one answer carries a `call_id`: `agent.snapshot.get`,
`agent.reply`, `agent.sessions.get`, `chat.history.get`, `chat.send` and `chat.interrupt` (and the
requests later versions add on the same pattern).

- The client chooses it: a string of 1 to 64 UTF-8 bytes, different from every other call of
  that client that is still waiting in the session.
- The host answers a call with exactly one message carrying the same `call_id`: the matching
  answer (`agent.snapshot`, `agent.reply.result`, `agent.sessions`, `chat.history`,
  `chat.send.result`, `chat.interrupt.result`), or an `error` that carries it.
- A client drops an answer whose `call_id` it is no longer waiting for (for example because the
  call timed out).
- A missing, empty or longer-than-64-byte `call_id` on a message that requires one is `bad_json`.
- The P1 rule still holds: the host answers the `agent.reply` messages for one `request_id` in
  the order they arrived (section 5).

## 4. Messages

| `t` | Sender | When | Fields |
| --- | --- | --- | --- |
| `hello` | client | First frame after the handshake | `client_version` string, `device_name` string |
| `welcome` | host | Reply to an acceptable `hello` | `protocol_version` int, `host_version` string, `machine_name` string |
| `error` | either | A request cannot be honored | `code` string, `message` string (human readable), `call_id` string, optional: set when the error answers that call |
| `agent.snapshot.get` | client | After `welcome`, and whenever it wants a full resync | `call_id` string |
| `agent.snapshot` | host | Reply to `agent.snapshot.get` | `call_id` string, `revision` int, `pending` array of PendingItem |
| `agent.changed` | host | Whenever the pending set changes | `revision` int, `added` array of PendingItem, `resolved` array of request_id strings |
| `agent.reply` | client | The user decides on a pending item | `call_id` string, `request_id` string, `decision` object (Decision) |
| `agent.reply.result` | host | Reply to every `agent.reply` | `call_id` string, `request_id` string, `outcome` string |
| `agent.sessions.get` | client | Whenever it wants the session list: after `welcome`, and for a resync | `call_id` string |
| `agent.sessions` | host | Reply to `agent.sessions.get` | `call_id` string, `revision` int, `sessions` array of AgentSession |
| `agent.sessions.changed` | host | Whenever the session list changes | `revision` int, `upserted` array of AgentSession, `removed` array of `session_id` strings |
| `chat.history.get` | client | The user opens a session, or scrolls to older entries | `call_id` string, `session_id` string, `before_seq` int (optional), `limit` int (1 to 50) |
| `chat.history` | host | Reply to `chat.history.get` | `call_id` string, `session_id` string, `entries` array of ChatEntry (oldest first), `has_more` bool |
| `chat.entries` | host | A transcript entry is added or changes | `session_id` string, `entries` array of ChatEntry (upsert by `id`) |
| `chat.send` | client | The user sends a message to a session | `call_id` string, `session_id` string, `text` string (1 to 16 384 UTF-8 bytes) |
| `chat.send.result` | host | Reply to every acceptable `chat.send` | `call_id` string, `outcome` string |
| `chat.interrupt` | client | The user stops the session's current turn | `call_id` string, `session_id` string, `hard` bool |
| `chat.interrupt.result` | host | Reply to every `chat.interrupt` | `call_id` string, `outcome` string |
| `ping` | either | Keep-alive / latency probe | `nonce` uint64 |
| `pong` | either | Immediately after `ping`, echoing it | `nonce` uint64 (same value) |

Error codes in use: `protocol_mismatch`, `bad_request`, `too_large`, `unsupported` (the host has no
session list or no chat: it answers each such call with this code and its `call_id`), `not_found`
(`chat.history.get` for a `session_id` the host does not have). Others MAY be added; receivers treat
an unrecognized code as a generic error.

A host answers a `chat.history.get` whose `limit` is outside 1 to 50, and a `chat.send` whose `text` is
empty or longer than 16 384 UTF-8 bytes, with `error` `bad_request` carrying the `call_id`.

`revision` counts changes of the pending set. A host MUST raise it by exactly 1 with each
`agent.changed`, and an `agent.snapshot` at revision r includes every change up to r. A client
keeps the revision of the last snapshot or change it applied (its current revision), and for
each `agent.changed`:

- `revision` at or below the current one: it ignores the change, which it already has (for
  example from a snapshot taken after the change);
- `revision` exactly current + 1: it applies the change;
- `revision` above current + 1: it missed a change and MUST send `agent.snapshot.get`.

The session list has its own `revision`, a counter apart from the pending set's, and follows the same
rules: a host MUST raise it by exactly 1 with each `agent.sessions.changed`, an `agent.sessions` at
revision r includes every change up to r, and the client compares each `agent.sessions.changed` with
the revision of its last `agent.sessions` or applied change as above (ignore, apply, or resync with
`agent.sessions.get`).

### PendingItem

| Field | Type | Notes |
| --- | --- | --- |
| `request_id` | string | Unique, stable id of the request |
| `kind` | string | `permission`, `question`, `exit_plan` (open enum) |
| `agent` | string | `claude` in P1 |
| `workspace_id` | string | |
| `workspace_title` | string | |
| `tool_name` | string, optional | |
| `tool_input_preview` | string, optional | At most 8192 UTF-8 bytes (section 6) |
| `created_at_ms` | int64 | Unix time in milliseconds |
| `modes` | array of string | Required, may be empty: the decision modes the host accepts for this item. For a `permission`, `PermissionMode` strings, never `bypass`; for an `exit_plan`, `ExitPlanMode` strings; empty for a `question` |
| `questions` | array of PendingQuestion, optional | The questions of a `question` item |
| `plan_preview` | string, optional | The plan text of an `exit_plan` item. At most 8192 UTF-8 bytes (section 6) |

A client that meets an item whose `kind` it does not know shows a generic card ("open on the
Mac") with no buttons.

### PendingQuestion

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | |
| `header` | string, optional | Short title |
| `prompt` | string | The question text |
| `multi_select` | bool | Whether more than one option can be chosen |
| `options` | array of PendingQuestionOption | |

A PendingQuestionOption has `id` string, `label` string and `description` string (optional). A
decision selects options by `label`, or gives a free-text answer (section 4, Decision).

### Decision

The `decision` object of `agent.reply` has a `kind` (open enum) that selects the other fields:

| `kind` | Other fields | Example |
| --- | --- | --- |
| `permission` | `mode` string | `{"kind":"permission","mode":"once"}` |
| `question` | `selections` array of string, positional: `selections[i]` answers `questions[i]`, so its length equals the number of the item's `questions`. Each element is 1 to 1024 UTF-8 bytes. An element equal to an option `label` picks that option; any other string is a free-text answer. For a `multi_select` question, the chosen labels are joined with `", "` | `{"kind":"question","selections":["Postgres"]}` |
| `exit_plan` | `mode` string, `feedback` string (optional) | `{"kind":"exit_plan","mode":"manual","feedback":"split step 2"}` |

A `decision` with a `kind` this version does not know decodes (it is not `bad_json`); the host
answers it `unknown` (section 5). A known `kind` with a missing required field is `bad_json`.

### AgentSession

| Field | Type | Notes |
| --- | --- | --- |
| `session_id` | string | Unique, stable id of the session |
| `agent` | string | `claude` in P2 |
| `workspace_id` | string | |
| `workspace_title` | string | |
| `title` | string, optional | The session's own title; dropped first when the list does not fit (section 6) |
| `state` | string | `idle`, `working`, `needs_input`, `ended` (open enum) |
| `state_since_ms` | int64, optional | Unix time in milliseconds at which `state` began |
| `last_activity_ms` | int64, optional | Unix time in milliseconds of the last activity |

`upserted` in `agent.sessions.changed` adds a session or replaces the one with the same `session_id`;
`removed` lists the `session_id` of sessions that are gone.

### ChatEntry

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Stable id of the entry; `chat.entries` upserts by it |
| `rev` | int | Revision of the entry, required: see below |
| `seq` | int | Orders the entries of one session; `before_seq` of `chat.history.get` compares with it |
| `role` | string | `user`, `agent`, `system` (open enum) |
| `kind` | string | `prose`, `thought`, `tool_use`, `status`, `other` (open enum) |
| `text` | string | At most 4096 UTF-8 bytes, cut on a Unicode scalar boundary (section 6) |
| `truncated` | bool, optional | `true` when the host cut `text`; omitted when it did not |
| `tool_name` | string, optional | The tool of a `tool_use` entry |
| `ts_ms` | int64 | Unix time in milliseconds |

`chat.history` returns the newest `limit` entries whose `seq` is below `before_seq` (the newest
entries when `before_seq` is absent), oldest first; `has_more` is true when older entries exist. A
client keeps the entries it has by `id`: `chat.entries` and `chat.history` both upsert.

`rev` orders the emissions of one entry. The host gives every emission of an entry, in a `chat.history` or
a `chat.entries`, a `rev` strictly greater than that of any earlier emission of the same `id`. The two
messages travel independently, so an older emission can arrive after a newer one: a receiver that already
holds an entry with this `id` keeps whichever has the higher `rev` (equal `rev` means the same content)
and drops the other. A host takes `rev` from its transcript source.

### Enums (exact strings, all open)

- `PermissionMode` (`mode` of a `permission` decision): `once`, `always`, `all`, `deny`.
- `ExitPlanMode` (`mode` of an `exit_plan` decision): `ultraplan`, `auto_accept`, `manual`, `deny`.
- `outcome` of `agent.reply.result`: `delivered`, `already_handled`, `unknown`.
- `state` (AgentSession): `idle`, `working`, `needs_input`, `ended`.
- `role` (ChatEntry): `user`, `agent`, `system`. `kind` (ChatEntry): `prose`, `thought`, `tool_use`, `status`, `other`.
- `outcome` of `chat.send.result`: `submitted`, `not_found`, `busy`, `failed`. A `chat.send` for a
  `session_id` the host does not have gets the outcome `not_found`, not an `error`.
- `outcome` of `chat.interrupt.result`: `sent`, `not_found`, `failed`.

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
3. A decision that does not fit the item: the host answers `unknown` and leaves the item as it
   was. That is any of: the `decision.kind` differs from the item's `kind`; the decision's
   `mode` is not in the item's `modes`; for a `question`, the number of `selections` differs from
   the number of the item's `questions`, or an element is empty or longer than 1024 UTF-8 bytes;
   the `decision.kind` is not known to the host.
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

`tool_input_preview` and `plan_preview` are cut by the host to at most 8192 UTF-8 bytes. Every cut falls on a
Unicode scalar boundary: the result is valid UTF-8, never a split character. The client treats
the previews as display text only, not as the complete tool input or plan.

Several items of 8 KiB previews can overflow the frame limit (eight already do). If an
`agent.snapshot` or `agent.changed` frame would exceed 65 519 bytes, the host shrinks the
previews in steps and re-encodes after each step, stopping at the first that fits:

1. every `tool_input_preview` and `plan_preview` truncated to at most 8192 bytes;
2. every `tool_input_preview` and `plan_preview` truncated to at most 1024 bytes;
3. `tool_input_preview` and `plan_preview` omitted on every item.

If the frame still does not fit after step 3, the host MUST NOT send it. When it was the answer
to a call, the host sends `error` with code `too_large` and that `call_id` instead, so the call
still gets exactly one answer (section 3); the client fails that call. This holds for every
answer to a call, not only snapshots. A push that answers no call, such as `agent.changed`, is
logged and dropped; a client recovers through `agent.snapshot.get`, which the host answers with
the same rule.
Splitting one logical message into several frames is not defined in v1, except for `chat.entries`
(below).

`text` of a ChatEntry is at most 4096 UTF-8 bytes, cut on a Unicode scalar boundary, with `truncated` set
to `true` when it was cut. The host enforces this on every entry it sends, whatever its transcript source gave. Besides the snapshot rule above,
three more rules apply:

- `chat.history`: the host drops the oldest entries, one at a time, until the frame fits, and sets
  `has_more` to `true`. The client pages back with `before_seq` set to the `seq` of the oldest entry it
  received. If not even an empty page fits, the call is answered `error` `too_large`.
- `chat.entries`: the host splits the entries into several `chat.entries` frames, each complete by
  itself (every entry is an upsert), in order. An entry that does not fit alone is logged and dropped.
- `agent.sessions` (and `agent.sessions.changed`): the host drops the `title` of every session. If the
  frame still does not fit, the host does not send it: an `agent.sessions` call is answered `error`
  `too_large` with its `call_id`, and an `agent.sessions.changed` is logged and dropped (the client
  recovers through the revision gap rule and `agent.sessions.get`).

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
  `error` with code `bad_request`, carrying the frame's `call_id` when that could be read (a valid
  1 to 64 byte string), and keeps the session. A client fails the call that `error` names. Received by the client, it drops the
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
  For `bad_json`, `call_id` (when present) is the call id the decoder reports with the error; when
  absent, none is reported.
- `boundary_frames`: generated frames. Frame text = `prefix` + filler + `suffix`, where filler is
  each `{text, count}` repeated and concatenated. Entries check exactly 65 519 bytes (accepted),
  65 520 bytes (`frame_too_large`) and multi-byte content whose byte count exceeds the limit while
  its character count does not. Encoding the `error` message with that filler as `message` must
  succeed or fail the same way.

`message.case` names the message; the other `message` keys use the JSON field names (`decision`
and PendingItem objects use their wire form). All 21 cases:

| `message.case` | Wire `t` | Other keys |
| --- | --- | --- |
| `hello` | `hello` | `client_version`, `device_name` |
| `welcome` | `welcome` | `protocol_version`, `host_version`, `machine_name` |
| `error` | `error` | `code`, `message`, `call_id` (optional) |
| `snapshot_get` | `agent.snapshot.get` | `call_id` |
| `snapshot` | `agent.snapshot` | `call_id`, `revision`, `pending` |
| `changed` | `agent.changed` | `revision`, `added`, `resolved` |
| `reply` | `agent.reply` | `call_id`, `request_id`, `decision` |
| `reply_result` | `agent.reply.result` | `call_id`, `request_id`, `outcome` |
| `ping` | `ping` | `nonce` |
| `pong` | `pong` | `nonce` |
| `sessions_get` | `agent.sessions.get` | `call_id` |
| `sessions` | `agent.sessions` | `call_id`, `revision`, `sessions` (AgentSession objects) |
| `sessions_changed` | `agent.sessions.changed` | `revision`, `upserted`, `removed` |
| `chat_history_get` | `chat.history.get` | `call_id`, `session_id`, `before_seq` (optional), `limit` |
| `chat_history` | `chat.history` | `call_id`, `session_id`, `entries` (ChatEntry objects), `has_more` |
| `chat_entries` | `chat.entries` | `session_id`, `entries` |
| `chat_send` | `chat.send` | `call_id`, `session_id`, `text` |
| `chat_send_result` | `chat.send.result` | `call_id`, `outcome` |
| `chat_interrupt` | `chat.interrupt` | `call_id`, `session_id`, `hard` |
| `chat_interrupt_result` | `chat.interrupt.result` | `call_id`, `outcome` |
| `unknown` | any unrecognized `t` | `type` (the `t` value); decode-only |
