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
  `unknown` (forward compatibility), whatever its other fields hold; it keeps the frame's `call_id`
  when that is a valid one (a string of 1 to 64 UTF-8 bytes), and section 7 says how each side handles
  it; (5) if `t` is known but a field is
  missing or has the wrong type, `bad_json` (an unlisted enum value is not an error, see
  Extension). A known `t` never degrades to `unknown`.
- `unknown` is decode-only; an implementation MUST NOT be able to send it.

### Extension

- Every string enum field is an open enum: `kind` (of a PendingItem, of a decision, of a ChatEntry and
  of an `attach.begin`), `mode`, `outcome`, `state` (of an AgentSession), `role` (of a ChatEntry), and
  the enum fields later versions add. A value this version does not know still decodes (an
  implementation keeps the raw string, for example as `.other(raw)`); it is never `bad_json`.
- A sender MAY add an optional field at any time; receivers ignore fields they do not know.
- A host MAY add a push, a message that answers no call (such as `chat.reset`): a client that predates it
  ignores it (section 7), so it needs no new `v`. A new request that expects an answer carries a
  `call_id`, and a host that predates it answers `unsupported` (section 3).
- Adding a required field, or changing the meaning of a field, requires raising `v`.
- `v` stays 1 in P2: the P2 changes revise v1 before its first release, because no P1 build has
  left the spike.

### Call ids

Every request that expects exactly one answer carries a `call_id`: `agent.snapshot.get`,
`agent.reply`, `agent.sessions.get`, `chat.history.get`, `chat.send`, `chat.interrupt`, `attach.begin`,
`attach.chunk`, `attach.end`, `workspace.list.get`, `workspace.create`, `workspace.rename`,
`workspace.close`, `agent.close` and `terminal.close` (and the requests later versions add on the same pattern).

- The client chooses it: a string of 1 to 64 UTF-8 bytes, different from every other call of
  that client that is still waiting in the session.
- The host answers a call with exactly one message carrying the same `call_id`: the matching
  answer (`agent.snapshot`, `agent.reply.result`, `agent.sessions`, `chat.history`,
  `chat.send.result`, `chat.interrupt.result`, `attach.ready`, `attach.chunk.result`, `attach.end.result`,
  `workspace.list`, `workspace.create.result`, `workspace.rename.result`, `workspace.close.result`,
  `agent.close.result`, `terminal.close.result`), or an `error` that carries it.
- A client drops an answer whose `call_id` it is no longer waiting for (for example because the
  call timed out).
- A missing, empty or longer-than-64-byte `call_id` on a message that requires one is `bad_json`.
- A call the host does not know (a request type of a later version, sent by a newer client) still gets
  its one answer: the host answers a frame of unknown `t` that carries a valid `call_id` with `error`
  `unsupported` and that `call_id`, so the client fails the call at once instead of waiting for its
  timeout. A frame of unknown `t` without a valid `call_id` gets no answer.
- The P1 rule still holds: the host answers the `agent.reply` messages for one `request_id` in
  the order they arrived (section 5).

## 4. Messages

| `t` | Sender | When | Fields |
| --- | --- | --- | --- |
| `hello` | client | First frame after the handshake | `client_version` string, `device_name` string |
| `welcome` | host | Reply to an acceptable `hello` | `protocol_version` int, `host_version` string, `machine_name` string, `features` array of strings (optional, omitted when empty; see Features) |
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
| `chat.reset` | host | The session's transcript was replaced: the entries the client holds for it are gone (see ChatEntry) | `session_id` string |
| `chat.send` | client | The user sends a message to a session | `call_id` string, `session_id` string, `text` string (0 to 16 384 UTF-8 bytes; at least 1 unless `attachments` is present), `attachments` array of 1 to 5 `attachment_id` strings (optional, omitted when none; section 5) |
| `chat.send.result` | host | Reply to every acceptable `chat.send` | `call_id` string, `outcome` string |
| `chat.interrupt` | client | The user stops the session's current turn | `call_id` string, `session_id` string, `hard` bool |
| `chat.interrupt.result` | host | Reply to every `chat.interrupt` | `call_id` string, `outcome` string |
| `attach.begin` | client | The user attaches a photo or file to a message: first step of an upload (section 5) | `call_id` string, `kind` string, `name` string, `size` int (1 to 10 485 760) |
| `attach.ready` | host | Reply to an acceptable `attach.begin` | `call_id` string, `attachment_id` string (chosen by the host: 1 to 64 UTF-8 bytes) |
| `attach.chunk` | client | The next piece of an upload, after `attach.ready` | `call_id` string, `attachment_id` string, `offset` int, `data` string (standard base64 with padding of 1 to 45 000 bytes) |
| `attach.chunk.result` | host | Reply to every acceptable `attach.chunk` | `call_id` string, `attachment_id` string, `received` int (bytes the host holds so far) |
| `attach.end` | client | Every byte has been sent | `call_id` string, `attachment_id` string, `sha256` string (64 lowercase hex characters: the SHA-256 of all bytes) |
| `attach.end.result` | host | Reply to an acceptable `attach.end`: the upload is complete and can be named in a `chat.send` | `call_id` string, `attachment_id` string |
| `workspace.list.get` | client | Whenever it wants the workspace list: after `welcome` when the host lists `workspaces` (Features), and for a resync | `call_id` string |
| `workspace.list` | host | Reply to `workspace.list.get` | `call_id` string, `revision` int, `workspaces` array of Workspace |
| `workspace.changed` | host | Whenever the workspace list changes | `revision` int, `upserted` array of Workspace, `removed` array of `workspace_id` strings |
| `workspace.create` | client | The user makes a new workspace on the Mac. It carries no path, command or program name: the Mac chooses the directory, as when the user adds a workspace there | `call_id` string |
| `workspace.create.result` | host | Reply to every `workspace.create` | `call_id` string, `outcome` string, `workspace_id` string (the new workspace; present only when `outcome` is `ok`) |
| `workspace.rename` | client | The user renames a workspace | `call_id` string, `workspace_id` string, `title` string (at most 512 UTF-8 bytes) |
| `workspace.rename.result` | host | Reply to every acceptable `workspace.rename` | `call_id` string, `outcome` string |
| `workspace.close` | client | The user closes a workspace on the Mac | `call_id` string, `workspace_id` string |
| `workspace.close.result` | host | Reply to every `workspace.close` | `call_id` string, `outcome` string |
| `agent.close` | client | The user closes an agent's terminal tab on the Mac | `call_id` string, `session_id` string |
| `agent.close.result` | host | Reply to every `agent.close` | `call_id` string, `outcome` string |
| `terminal.close` | client | The user closes one terminal tab of a workspace on the Mac | `call_id` string, `workspace_id` string, `terminal_id` string |
| `terminal.close.result` | host | Reply to every `terminal.close` | `call_id` string, `outcome` string |
| `ping` | either | Keep-alive / latency probe | `nonce` uint64 |
| `pong` | either | Immediately after `ping`, echoing it | `nonce` uint64 (same value) |

Error codes in use: `protocol_mismatch`, `bad_request`, `too_large` (an answer that does not fit a frame,
section 6, or an `attach.begin` whose `size` is above the limit, section 5), `unsupported` (the host has no
session list or no chat, takes no attachments, lists no workspaces, takes no workspace control, no agent
control or no terminal control, or does not know the call's `t`: it answers each such call with this code and its
`call_id`), `not_found` (`chat.history.get` for a `session_id` the host does not have). Others MAY be added; receivers treat
an unrecognized code as a generic error.

A host answers a `chat.history.get` whose `limit` is outside 1 to 50, and a `chat.send` whose `text` is
longer than 16 384 UTF-8 bytes, or empty without `attachments`, with `error` `bad_request` carrying the
`call_id`. With `attachments` (1 to 5 ids) the `text` MAY be empty: a message can be only a photo or a file.
More than 5 ids is `bad_request` too.

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

The workspace list has a third counter, apart from the other two, and follows the same rules: a host MUST raise
it by exactly 1 with each `workspace.changed`, a `workspace.list` at revision r includes every change up to r, and
the client compares each `workspace.changed` with the revision of its last `workspace.list` or applied change as
above (ignore, apply, or resync with `workspace.list.get`).

### Features

`welcome.features` lists the optional capabilities the host offers; it is omitted when the host offers none,
and a receiver reads an absent `features` as an empty list. A client uses a capability only when the host
lists it, and ignores a string it does not know. These features are defined:

- `attachments`: the host takes `attach.*` uploads and `chat.send.attachments` (section 5).
- `workspaces`: the host answers `workspace.list.get` and pushes `workspace.changed` (Workspace).
- `workspace_control`: the host takes `workspace.create`, `workspace.rename` and `workspace.close` (Workspace).
- `agent_close`: the host takes `agent.close` (Workspace).
- `terminal_close`: the host takes `terminal.close` (Workspace).

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
| `exit_plan` | `mode` string, `feedback` string (optional, at most 4096 UTF-8 bytes) | `{"kind":"exit_plan","mode":"manual","feedback":"split step 2"}` |

An `exit_plan` decision whose `feedback` is not empty (after trimming white space) rejects the plan and asks
the agent to revise it with that change, whatever `mode` says: the host answers the agent "rejected, wants
this change: <feedback>". `mode` takes effect only without feedback, but it is still required and must be one
of the item's `modes`.

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

### Workspace

| Field | Type | Notes |
| --- | --- | --- |
| `workspace_id` | string | Unique, stable id of the workspace; the same value as `workspace_id` of an AgentSession and of a PendingItem of that workspace |
| `title` | string | The workspace's name on the Mac |
| `order` | int | Position in the Mac's sidebar: with several windows, window order, then order within the window |
| `directory` | string, optional | Display text for the working directory, with the home directory written `~`. Read-only: no call takes it. Dropped when the list does not fit (section 6) |
| `branch` | string, optional | The git branch of `directory`. Dropped when the list does not fit |
| `ports` | array of int, optional | Ports the workspace's processes listen on. The first thing the host drops to fit a frame |
| `terminals` | array of Terminal | The workspace's terminal surfaces, in tab order; may be empty |

A Terminal has these fields:

| Field | Type | Notes |
| --- | --- | --- |
| `terminal_id` | string | Unique, stable id of the terminal: the surface id on the Mac |
| `title` | string | The tab's name. The last thing the host drops to fit a frame: it becomes `""` (section 6) |
| `order` | int | Position among the workspace's terminals |
| `selected` | bool | Whether the Mac has this terminal selected in its workspace. A client uses it only to pick its default tab |
| `session_id` | string, optional | The Claude Code session running in this terminal, matching `session_id` of an AgentSession; absent when none runs there |

The list holds only the Mac's own local workspaces (not SSH or other remote ones) and only their terminal
surfaces: browser, Markdown and other panels do not appear. Workspace groups do not appear either: the list is flat,
in sidebar order. It carries no state and no pending question: a client derives them from the session list and the
pending items (`agent.sessions`, `agent.snapshot`).

`upserted` in `workspace.changed` adds a workspace or replaces the one with the same `workspace_id` (with its whole
`terminals` array); `removed` lists the `workspace_id` of workspaces that are gone. The revision rules are those of
the session list (above).

The three control calls (`workspace_control`) act on the Mac and answer with an `outcome` (Enums):

- `workspace.create` makes a workspace without changing the Mac's selection or bringing its window to the front, and
  answers `ok`, normally with the new `workspace_id`. The field is optional: a client that gets `ok` without it
  reads the list again. `workspace.create.result` and the `workspace.changed` that lists the new workspace may
  arrive in either order, so a client that has the id before the list waits for the list.
- `workspace.rename` sets `title`. A `title` longer than 512 UTF-8 bytes is `error` `bad_request` carrying the
  `call_id`. The host cleans the title first (it removes control characters and the whitespace around it); a title
  left empty by that answers `failed`. There is no "clear the name" call: an empty title never takes the Mac back
  to its automatic name.
- `workspace.close` closes the workspace and its terminals. The Mac keeps its own rules: it can answer `refused`, for
  example for a pinned workspace or the last workspace of a window.

A `workspace_id` the host does not have is `not_found`, not an `error`. A command answers `refused` when the Mac
blocks remote control. A client does not resend a control call after losing the connection: the host may already
have acted, so it reads the list again.

`agent.close` closes the terminal tab of a live agent session the host lists in a local workspace, without asking. On
its workspace's last tab (of any kind) the Mac closes the workspace, as its Close Tab does by default; with its "Keep
Workspace Open When Closing Last Surface" setting on it answers `refused` and closes nothing. `not_found` for an
unknown, ended or tab-less session. Like a control call it answers with an `outcome`, and a client does not resend
it after losing the connection: the host may already have acted, so it reads the session list again.

`terminal.close` (`terminal_close`) closes one terminal tab of a workspace the host lists, by the `workspace_id` of
a Workspace and the `terminal_id` of one of its Terminal objects, without asking. It looks for no agent: the user
picked the tab, so it closes whatever runs there. A pair that is not a terminal of that workspace in the host's list
is `not_found` and nothing closes: an id the host does not have, a terminal of another workspace, a tab that is
already gone, and every id of an SSH or other remote workspace, which is never listed. On the workspace's last
tab the Mac closes the workspace, as its Close Tab does by default; with its "Keep Workspace Open When Closing
Last Surface" preference on it answers `refused` and closes nothing, and its rules for closing a workspace still
hold (a pinned workspace, the last workspace of a window). Like `agent.close` it answers with an `outcome`, and a
client does not resend it after losing the connection: the host may already have acted, so it reads the
workspace list again.

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
entries when `before_seq` is absent), oldest first; `has_more` is true when older entries exist.
Entries that share a `seq` belong to one transcript line; a `chat.history` page never contains part of
a `seq` group (section 6), and `before_seq` pages strictly older groups. A
client keeps the entries it has by `id`: `chat.entries` and `chat.history` both upsert. A session the host
lists whose agent has not written its transcript yet has an empty history (`entries` empty, `has_more`
false), not `not_found`; its entries arrive in `chat.entries` once written.

`rev` orders the emissions of one entry. The host gives every emission of an entry, in a `chat.history` or
a `chat.entries`, a `rev` strictly greater than that of any earlier emission of the same `id`. The two
messages travel independently, so an older emission can arrive after a newer one: a receiver that already
holds an entry with this `id` keeps whichever has the higher `rev` (equal `rev` means the same content)
and drops the other. A host takes `rev` from its transcript source.

`chat.reset` says a session's transcript was replaced: the host reloaded it from scratch, for example
because the agent was resumed into a rewritten file, or a forked session's file first appeared already
holding a whole history. The entries a client holds for that session, their `seq` values and its
`before_seq` position no longer apply. A host sends `chat.reset` in order with that session's
`chat.entries`: every entry pushed before it belongs to the old transcript, every entry after it to the
new one. On `chat.reset` a client:

- drops every entry it holds for that session;
- drops the answer to any `chat.history.get` for that session it sent before the reset;
- pages again from the newest (`chat.history.get` without `before_seq`), keeping the `chat.entries` that
  arrive meanwhile (they upsert as usual).

A client that predates `chat.reset` ignores it (unknown `t`, section 7) and keeps the old entries until
it opens the session again.

### Enums (exact strings, all open)

- `PermissionMode` (`mode` of a `permission` decision): `once`, `always`, `all`, `deny`.
- `ExitPlanMode` (`mode` of an `exit_plan` decision): `ultraplan`, `auto_accept`, `manual`, `deny`.
- `outcome` of `agent.reply.result`: `delivered`, `already_handled`, `unknown`.
- `state` (AgentSession): `idle`, `working`, `needs_input`, `ended`.
- `role` (ChatEntry): `user`, `agent`, `system`. `kind` (ChatEntry): `prose`, `thought`, `tool_use`, `status`, `other`.
- `outcome` of `chat.send.result`: `submitted`, `not_found`, `busy`, `failed`. A `chat.send` for a
  `session_id` the host does not have gets the outcome `not_found`, not an `error`; so does one for a listed
  session whose agent is not live, an `ended` one for example (section 10).
- `outcome` of `chat.interrupt.result`: `sent`, `not_found`, `failed`, with the same `not_found` rule.
- `kind` (`attach.begin`): `image`, `file`.
- `outcome` of `workspace.create.result`, `workspace.rename.result`, `workspace.close.result` and
  `agent.close.result`: `ok`, `not_found`, `refused` (the Mac blocks remote control, or its own rule says no, such as
  closing a pinned workspace, the last workspace of a window, or an agent's last tab while "Keep Workspace Open When
  Closing Last Surface" is on), `failed`.
- `outcome` of `terminal.close.result`: `ok`, `not_found`, `refused`, `failed`, as for `agent.close.result`; a
  terminal that is not in a workspace the host lists is `not_found`, and a workspace's last tab with "Keep Workspace
  Open When Closing Last Surface" on is `refused`.

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
   for an `exit_plan`, the `feedback` is longer than 4096 UTF-8 bytes; the `decision.kind` is not
   known to the host.
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

### Attachments

A phone attaches photos and files to a `chat.send` by uploading them first. The host offers this only when
`welcome.features` lists `attachments` (Features, section 4); a host without it answers every `attach.*`
call `error` `unsupported` with its `call_id`, so a phone never needs to try. It answers a `chat.send` that
carries `attachments` the same way and types nothing, not even the text. One upload runs in these
steps, each a call (section 3):

1. `attach.begin` states the `kind` (`image` or `file`, an open enum), the `name` and the `size` in bytes.
   The host answers `attach.ready` with an `attachment_id` it chose, a string of 1 to 64 UTF-8 bytes.
2. `attach.chunk` carries the bytes in order. The client sends the next chunk only after the
   `attach.chunk.result` of the previous one.
3. `attach.end` carries the SHA-256 of all the bytes. The host answers `attach.end.result`.
4. `chat.send` names the finished uploads in `attachments`.

Rules:

- `size` is 1 to 10 485 760 (10 MiB). A larger `size` is answered `error` `too_large`, a smaller one
  `bad_request`, and nothing is stored.
- A `kind` other than `image` and `file` is answered `error` `bad_request`, and nothing is stored.
- Chunks arrive in order. `offset` MUST equal the number of bytes the host holds for that upload, `data` is
  1 to 45 000 bytes before base64, and the total never passes `size`. A chunk that breaks any of these is
  answered `error` `bad_request` and is not applied.
- `data` is standard base64 (RFC 4648 section 4) with padding, with no line breaks and no other characters.
  `sha256` is 64 lowercase hex characters. Anything else there is `bad_json` (section 3). A full chunk is
  60 000 base64 characters, which fits a frame with room for 64-byte ids (section 3).
- `attach.end` before `size` bytes have arrived, or with a digest that is not the SHA-256 of the bytes, is
  answered `error` `bad_request`, and the host drops the upload.
- An `attachment_id` means something only in the Link session that made it, and ends with that session
  (a new session, even of the same phone, cannot use it).
- An upload is used by one `chat.send` only. Once the host accepts a `chat.send` that names it, it removes the
  upload at once, whatever outcome the `chat.send.result` then reports.
- A client uploads one attachment at a time, and sends one message's uploads and its `chat.send` with no upload
  of another message in between: it starts the next message's first `attach.begin` only once that `chat.send`
  is answered or has failed. An `attach.begin` therefore first drops every upload of the session that has not had its
  `attach.end`, whatever its progress, so an upload that failed or was given up never holds a place.
- A session holds at most 5 finished uploads that no `chat.send` has used yet, counted after that drop. An
  `attach.begin` that the host accepts while it holds 5 first drops the one whose `attach.end` came first.
  Under the rule above that is never an upload of the message going up (it has at most 5, and they ended last),
  only one left by a message that failed or was given up, so a phone's retry is never refused for its own
  earlier attempt.
- Once 5 minutes pass with no `attach.*` call that the host accepted (answered with anything but `error`),
  the host drops every upload of the session. The time counts from the session's last accepted call, not from
  each upload, so a slow message whose first upload ended long before its last keeps them all. A host may defer
  this check until it handles the next `attach.*` call or `chat.send`; a dropped id is answered `bad_request`
  like any id the host does not hold.
- A `chat.send` that names an `attachment_id` the host does not hold, an upload that has not had its
  `attach.end`, or the same id twice, is answered `error` `bad_request`; it is not accepted, so it uses none
  of the uploads.
- `name` is only a label that the phone suggests. The host never uses it as a path; section 10 says how it
  stores a file.

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

- `chat.history`: the host drops the oldest whole `seq` group (every entry with the smallest remaining
  `seq`) at a time until the frame fits, and sets `has_more` to `true`. A page therefore never contains
  part of a `seq` group. The client pages back with `before_seq` set to the `seq` of the oldest entry it
  received, which returns strictly older groups, so no entry is skipped. If even the newest group does
  not fit (after the 4096-byte text cap), the call is answered `error` `too_large`.
- `chat.entries`: the host splits the entries into several `chat.entries` frames, each complete by
  itself (every entry is an upsert), in order. An entry that does not fit alone is logged and dropped.
- `agent.sessions` (and `agent.sessions.changed`): the host drops the `title` of every session. If the
  frame still does not fit, the host does not send it: an `agent.sessions` call is answered `error`
  `too_large` with its `call_id`, and an `agent.sessions.changed` is logged and dropped (the client
  recovers through the revision gap rule and `agent.sessions.get`).
- `workspace.list` (and `workspace.changed`): the host shrinks every workspace in steps and re-encodes after each
  step, stopping at the first that fits. The steps add up, so each leaves less than the one before:
  1. every `ports` omitted;
  2. every `directory` omitted;
  3. every `branch` omitted;
  4. the `title` of every terminal becomes `""`.

  The `title` of a workspace, its `order`, and the `terminal_id`, `order`, `selected` and `session_id` of its
  terminals are never dropped. If the frame still does not fit after step 4, the host does not send it: a
  `workspace.list` call is answered `error` `too_large` with its `call_id`, and a `workspace.changed` is logged
  and dropped (the client recovers through the revision gap rule and `workspace.list.get`). The host never sends
  a list with a workspace left out.

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
- **Unknown `t`**: the session is kept. The host answers a frame of unknown `t` that carries a valid
  `call_id` with `error` `unsupported` and that `call_id` (section 3), and ignores one without. The
  client ignores every frame of unknown `t`.
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
and PendingItem objects use their wire form). All 41 cases:

| `message.case` | Wire `t` | Other keys |
| --- | --- | --- |
| `hello` | `hello` | `client_version`, `device_name` |
| `welcome` | `welcome` | `protocol_version`, `host_version`, `machine_name`, `features` (optional) |
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
| `chat_reset` | `chat.reset` | `session_id` |
| `chat_send` | `chat.send` | `call_id`, `session_id`, `text`, `attachments` (optional) |
| `chat_send_result` | `chat.send.result` | `call_id`, `outcome` |
| `chat_interrupt` | `chat.interrupt` | `call_id`, `session_id`, `hard` |
| `chat_interrupt_result` | `chat.interrupt.result` | `call_id`, `outcome` |
| `attach_begin` | `attach.begin` | `call_id`, `kind`, `name`, `size` |
| `attach_ready` | `attach.ready` | `call_id`, `attachment_id` |
| `attach_chunk` | `attach.chunk` | `call_id`, `attachment_id`, `offset`, `data` (the base64 text) |
| `attach_chunk_result` | `attach.chunk.result` | `call_id`, `attachment_id`, `received` |
| `attach_end` | `attach.end` | `call_id`, `attachment_id`, `sha256` (the hex text) |
| `attach_end_result` | `attach.end.result` | `call_id`, `attachment_id` |
| `workspaces_get` | `workspace.list.get` | `call_id` |
| `workspaces` | `workspace.list` | `call_id`, `revision`, `workspaces` (Workspace objects, each with its Terminal objects) |
| `workspaces_changed` | `workspace.changed` | `revision`, `upserted`, `removed` |
| `workspace_create` | `workspace.create` | `call_id` |
| `workspace_create_result` | `workspace.create.result` | `call_id`, `outcome`, `workspace_id` (optional) |
| `workspace_rename` | `workspace.rename` | `call_id`, `workspace_id`, `title` |
| `workspace_rename_result` | `workspace.rename.result` | `call_id`, `outcome` |
| `workspace_close` | `workspace.close` | `call_id`, `workspace_id` |
| `workspace_close_result` | `workspace.close.result` | `call_id`, `outcome` |
| `agent_close` | `agent.close` | `call_id`, `session_id` |
| `agent_close_result` | `agent.close.result` | `call_id`, `outcome` |
| `terminal_close` | `terminal.close` | `call_id`, `workspace_id`, `terminal_id` |
| `terminal_close_result` | `terminal.close.result` | `call_id`, `outcome` |
| `unknown` | any unrecognized `t` | `type` (the `t` value), `call_id` (optional: the frame's valid `call_id`); decode-only |

## 9. Pairing and trust

A phone trusts a Mac only through a QR code the Mac shows, and a Mac trusts a phone only after the
user presses Allow on that Mac. The relay carries the request; it cannot create trust.

**Offer (QR code).** The Mac shows

```
shellx-link://pair?v=1&m=<machine_id>&s=<link_slot>&k=<host key>&c=<code>&n=<machine name>
```

`k` is the Mac's 32-byte Noise static public key and `c` a 16-byte one-time code from a system
random source; both are base64url without padding. `n` is the machine name, percent-encoded (only
`A-Z a-z 0-9 - . _ ~` stay literal). `v` MUST be `1`; a parser rejects another version, a missing or
repeated field, and keys or codes of the wrong length. An offer is valid for 300 seconds
(`PairingOffer.lifetime`).

**Proof.** The phone proves it scanned the offer without sending the code:

```
proof = HMAC-SHA256(key: code, message: "shellx-link-pair/1" || 0x00 || UTF-8(machine_id) || 0x00
                    || UTF-8(link_slot) || 0x00 || host_key (32 bytes) || client_key (32 bytes))
```

`client_key` is the phone's 32-byte Noise static public key; `machine_id`, `link_slot` and
`host_key` are the values the phone read from the QR code. The Mac recomputes the proof from its
own machine id, slot and host key and compares in constant time, so a QR substituted in transit
(same code, another host key or slot) cannot produce a proof the Mac accepts.
`spec/vectors/pairing.json` has a fixed vector.

**Field limits.** A parser rejects: any path after `pair`, a port, userinfo, a fragment or a
repeated key; `m` outside 1-64 characters of `A-Z a-z 0-9 -`; `s` outside 1-64 characters of the
base64url alphabet; `k` or `c` containing anything but the base64url alphabet (no `+`, `/`, `=`);
`n` outside 1-100 Unicode scalars, or containing a control character or a bidi override or isolate
(U+202A-U+202E, U+2066-U+2069).

**Same account.** Phone and Mac MUST be signed in to the same ShellX account; the relay only
accepts a pairing request for a machine of the phone's own account.

**Relay routes** (JSON; `Authorization: Bearer <token>`; errors are `{"error": {"code", "message"}}`;
`*_b64` fields are standard base64):

| Route | Caller | Purpose |
| --- | --- | --- |
| `POST /v1/auth/login` | phone | `{email, password, device: {kind: "mobile", platform: "ios", name, public_key}}` (`public_key` base64url) gives `{user_id, device_id, token}` |
| `POST /v2/phone-pairings` | phone | `{machine_id, client_key_b64, proof_b64}` gives `201 {pairing_id}` |
| `GET /v2/phone-pairings/:id` | phone | `{status: pending\|approved\|denied\|expired, machine?: {machine_id, name, link_slot}}` |
| `GET /v2/phone-pairings?role=target`, `POST .../:id/approve`, `POST .../:id/deny` | Mac | list, approve or deny requests to this Mac |
| `GET /v2/phone-grants` | phone | `{grants: [{grant_id, machine_id, name, platform, online, link_slot, fingerprint}]}` |
| `DELETE /v2/phone-grants/:id` | phone or Mac | remove access (`204`) |
| `POST /v2/relay/tickets` | phone | `{permission: "connect", lane: "link", target_machine_id}` gives `{ticket, expires_at_unix, relay_url}` |

**Rules.**

- The phone's key becomes trusted by the Mac only after the user presses Allow on the Mac; the Mac
  then adds `client_key` to its list of allowed phones. A pending request grants nothing.
- The phone pins the host key from the QR offer. It never takes a host key from the relay. When the
  pairing is approved, the `machine_id` and `link_slot` the relay returns MUST equal the offer's;
  otherwise the phone aborts and stores nothing.
- Every later connection is a Noise handshake (section 2) in which the phone accepts only the pinned
  host key, over a circuit to the pinned `link_slot`. The phone checks that the connect ticket the
  relay mints names that slot and carries the `connect` permission.
- The relay can only remove trust (delete a grant, stop routing); a compromised relay cannot make a
  phone trust another host or a Mac trust another phone.
- If the phone gives up (cancelled, 300-second client deadline) or rejects an approval, it asks
  the relay once to withdraw the request (`POST /v2/phone-pairings/:id/deny`), ignoring errors.
  Transient poll failures (network errors, HTTP 5xx) are retried until the deadline; 4xx aborts.
- The API base URL MUST be `https`, except for a loopback host (development). The phone never
  follows an HTTP redirect from the API.
- Tokens, passwords, tickets, keys, codes and proofs are never logged.

## 10. Phone commands

A phone can make the Mac act: decide an agent's pending request, type into an agent session, interrupt it,
close the terminal it runs in, close any terminal tab of a listed workspace, and make, rename or close a workspace.
This section is the safety analysis for those commands. It follows the rules a remote command channel must meet: deny by default, allow only the
calls a product flow needs, scope every call to objects the caller may touch, and never let a call execute
or open arbitrary content on the Mac.

**Default deny.** A host acts only on the calls in the table below. Every other `t` gets no effect: a
call of a later version is answered `error` `unsupported` (section 3), any other unknown frame is
ignored, and a host frame type sent by a client is ignored or answered `bad_request` (section 7). No
field of any message names a command line, a program, a directory or other path on the host, or a URL for
the host to open or run, and none names a terminal to type into (`chat.send` and `chat.interrupt` name an
agent session, and the host types only into that session's terminal: see Shell fall-through below). A call
names a workspace only to rename or close one that the host's own list holds (`workspace.rename`,
`workspace.close`), and `workspace.create` names nothing: the host chooses where the new workspace goes.
`agent.close` names an agent session and nothing else, and the host closes only the terminal that
session is bound to (Agents below). `terminal.close` names a workspace and one of its terminals in the host's own
list, to close that tab and for nothing else (Tabs below).
(`attach.begin.name` is a label that the host sanitises, never a path: see Attachments below.)

**Allowed calls.**

| Call | Effect on the Mac | Scope |
| --- | --- | --- |
| `agent.snapshot.get`, `agent.sessions.get`, `chat.history.get` | None (reads) | The pending requests and sessions of this Mac's Claude Code agents; the transcripts of listed sessions |
| `agent.reply` | Gives a decision to an agent hook that is waiting for it | One pending request, by `request_id`. Only the item's `modes` (never `bypass` or `bypassPermissions`, which stay on the Mac), at most once (section 5) |
| `chat.send` | Pastes `text` (0 to 16 384 bytes) at the agent's prompt in its terminal and submits it. With `attachments`, the host saves those uploads as files and types their paths too: the images' before the text, the other files' after it (below) | One live Claude Code session, by `session_id`; the uploads of this Link session, by `attachment_id` |
| `attach.begin`, `attach.chunk`, `attach.end` | Keeps the uploaded bytes in the host's memory. Writes no file: files are written only when a `chat.send` carries the upload to a *live* session | The uploads of this Link session, by `attachment_id`; at most 5 finished and unsent plus the one going up, each at most 10 MiB |
| `chat.interrupt` | Sends Esc, or ctrl-C when `hard`, to that agent's terminal | One live Claude Code session, by `session_id` |
| `workspace.list.get` | None (read) | The host's own local workspaces and their terminals: titles, display directories, git branches, listening ports, tab titles |
| `workspace.create` | Makes a workspace on the Mac, in a directory the Mac chooses as when the user adds a workspace there. Its terminal starts the user's default shell when it is first shown (the Mac creates it lazily). Does not change the Mac's selection or bring its window to the front | None named: the call carries only `call_id`, no path, command, program, URL or environment |
| `workspace.rename` | Sets the workspace's title (at most 512 UTF-8 bytes) | One local workspace in the host's list, by `workspace_id` |
| `workspace.close` | Closes that workspace and its terminals, ending what runs in them, as when the user closes it there. The Mac keeps its own rules: it refuses to close a pinned workspace or the last workspace of a window, and refuses every control call while device management blocks remote control | One local workspace in the host's list, by `workspace_id` |
| `agent.close` | Closes the terminal tab of that agent session, without asking, ending what runs in it. On the workspace's last tab (of any kind) it closes the workspace, as the Mac's Close Tab does by default; with the Mac's "Keep Workspace Open When Closing Last Surface" setting on it is `refused` and nothing closes. The Mac refuses while device management blocks remote control | One live Claude Code session in a local workspace of the host's list, by `session_id`; `not_found` for an unknown, ended or tab-less session |
| `terminal.close` | Closes that terminal tab, without asking, ending what runs in it, whether or not an agent runs there. On the workspace's last tab it closes the workspace, as the Mac's Close Tab does by default; with the Mac's "Keep Workspace Open When Closing Last Surface" preference on it is `refused` and nothing closes, and the Mac's rules for closing a workspace still hold (a pinned workspace, the last workspace of a window). The Mac refuses while device management blocks remote control | One terminal of a local workspace in the host's list, by `workspace_id` and `terminal_id`; `not_found` for any other pair |
| `ping` | None | |

**Scope.** The host serves only its own Claude Code agent sessions and their pending requests, and its own
local workspaces. `session_id`, `request_id`, `workspace_id` and `terminal_id` are looked up in the host's own
lists; an id it does not have is `not_found` (`unknown` for a reply). A phone cannot name a workspace that is not
in the list (an SSH or other remote workspace never is), nor a file, machine or account, nor a terminal outside
those workspaces; `terminal.close` reaches a terminal of a listed workspace by its `terminal_id`, and `agent.close`
reaches a terminal only through a live agent session the host lists in one of those local workspaces. Only a
phone the Mac trusts gets this far: signed in to the same account, holding a proof from a QR code the Mac
showed, and allowed by the user on that Mac (section 9).

**Shell fall-through.** `chat.send` and `chat.interrupt` type into the terminal the agent runs in, and
`agent.close` closes it. Once the agent has exited, that terminal runs the user's shell or whatever started
next: a message would run there as a command line, ctrl-C would stop another program, and closing it would
end the user's shell. A host therefore accepts all three only for a *live* session: one that is not `ended`,
whose agent process the host knows by process id, and whose process is alive when the call arrives. Any
other session, including every ended session it lists (they stay listed for their read-only history), is
answered `not_found` before any terminal is touched. A session whose agent process the host has not learned
yet is `not_found` until the agent's next hook names it. The host then types into, or closes, only the
terminal that session is bound to, and only while that terminal still exists and still hosts the agent; it
never sends the text to, or closes, another terminal. What remains is the moment between that check and the
typing: an agent that exits within it can still let one message reach the terminal, the same window the
Mac's own remote-control path has. For `agent.close` the same moment lets a terminal that has just turned
into the user's shell be closed.

**Attachments.** `attach.*` lets a phone put files on the Mac, so what it may choose is narrow. The phone
never picks a path: the host names the directory, the file name and the file mode. An image is saved the
way a pasted clipboard image is, in the host's own temporary directory under a name the host chooses; the
extension is the only part taken from `name`, and only when it is a known image type (`png` otherwise).
A file goes in `shellx-attachments/<UUID>/<sanitized name>` inside that directory, a new UUID directory
for every file, with mode 0600 (the directories 0700). The host builds `<sanitized name>` from `name` by
removing `/`, `\`, control characters, line and paragraph separators and leading dots, cutting it so that
its canonically decomposed form (NFD) is at most 100 UTF-8 bytes (keeping the extension), and using `file`
when nothing is left, so the name cannot leave its directory, and a file system that stores names
decomposed cannot grow it past the 255 bytes a path component may take. The host registers every file it
saves (and the directory of a file) for the temporary-file cleanup it already runs for pasted images. It
never opens, previews or runs an attachment, and nothing is written until a `chat.send` carries the upload
to a live session (the shell fall-through rule above applies to the paths exactly as it does to `text`). The
paths are typed, escaped for the shell, only into the terminal of that live session, as the text is, and
never into another terminal: the images' paths first (the agent turns each into an attached image), then
the text, then the other files' paths, then the submit key. A message with text therefore never starts with
the raw path of a file, which an agent could take for one of its slash commands; a message of files only
does start with one.

What a phone can make the Mac hold is bounded, though not by a single figure:

- Memory, per Link session: at most 5 finished uploads that no `chat.send` has used plus the one going up,
  each at most 10 MiB. An upload dies with its session, with the `chat.send` that uses it, with the next
  `attach.begin` if it was not finished or if it is the oldest of 5, or once 5 minutes pass with no accepted
  `attach.*` call. A `chat.send` the host accepted takes its uploads (at most 5 of 10 MiB) out of that count
  and holds them until it is typed; one waiting behind an earlier message to the same session (sends to one
  session are typed one after another) keeps holding them meanwhile. The ShellX phone starts the next message
  with attachments only once the last one is answered (or its answer timed out), so it has about one such
  message in flight per Mac; a client that pipelines more makes the host hold up to 50 MiB more for each
  until the messages ahead of it are typed.
- Disk: each message writes at most 5 files of at most 10 MiB in the host's temporary directory. They are
  not removed when the agent has read them: they stay until the Mac app quits, which removes every file it
  registered (after a crash, the system's own clean-up of temporary files takes them). Disk use therefore
  grows with the messages a phone sends while the app runs, as it does with images the user pastes at the
  Mac.

What the agent then does with the path is the agent's own business, as with any path the user types at
its prompt, and a paired phone is trusted like the user (below). The host never logs attachment names or
bytes. The cmux socket method `mobile.chat.send` does not accept files (it
answers `invalid_params`); only ShellX Link does.

**Workspaces.** `workspace.*` is the one place where a phone makes the Mac start something, so it answers the
three questions a remote command channel must answer, one by one.

- Does it run commands or open content on the Mac? Only `workspace.create` starts anything: a workspace whose
  terminal starts the user's default shell when it is first shown, in a directory the Mac chooses, exactly as
  when the user presses the add button on the Mac. No call carries a command line, path, directory, environment variable, URL or program name, and no
  call types into that shell: `chat.send` still reaches only the terminal of a live agent (Shell fall-through
  above). The phone does not select the new workspace on the Mac, nor bring a window forward.
- Does it change or destroy what the phone does not own? The only objects are this Mac's own local workspaces,
  found by `workspace_id` in the host's list; any other id is `not_found`, and SSH or other remote workspaces
  are not listed, so they can be neither renamed nor closed. `workspace.close` keeps the Mac's rules: the Mac
  answers `refused` for a pinned workspace or the last workspace of a window. A rename is bounded by 512 UTF-8 bytes, which the host checks
  before it asks the Mac.
- Does it read state the phone has no business seeing? `workspace.list` carries what the user sees in the
  Mac's sidebar and tab bar (names, display directories with `~` for the home directory, branches, ports),
  and which agent session runs in which terminal. It carries no screen content, file, environment variable or
  setting.

**Agents.** `agent.close` is the one call that ends an agent for good, so it answers the same three questions.

- Does it run commands or open content on the Mac? No. The call carries only a `session_id`: no text, key,
  path, command, program or URL, and nothing is typed into any terminal. Closing the terminal ends what runs
  in it, as the user's Close Tab does. The Mac does not ask again: a phone is expected to have asked its user.
- Does it change or destroy what the phone does not own? It reaches only a live Claude Code agent that the
  host itself lists, in a local workspace that the host lists too. A session in an SSH or other remote workspace
  is never listed there, so it is `not_found` and nothing closes. The shell fall-through rule above applies: a
  session that has ended, whose agent process the host does not know by process id, or whose process is no
  longer alive when the call arrives is answered `not_found` before any terminal is touched, so once the agent
  has exited its terminal, which now runs the user's shell, cannot be closed by a phone. The host closes only
  the terminal that session is bound to, and only while that terminal still exists and still hosts the agent,
  in the workspace the host's list shows it in now (a tab dragged to another workspace closes there). When that
  terminal is the last tab of its workspace (counting tabs of every kind, not only terminals), the Mac closes
  the workspace, as its Close Tab does by default; with its "Keep Workspace Open When Closing Last Surface"
  setting on it answers `refused` and closes nothing. The Mac's rules for closing a workspace still hold (a
  pinned workspace, the last workspace of a window): the answer is `refused`.
- Does it read state the phone has no business seeing? No. The answer is an `outcome` and nothing else.

**Tabs.** `terminal.close` closes one tab by name, so it answers the same three questions.

- Does it run commands or open content on the Mac? No. The call carries two ids: no text, key, path, command,
  program or URL, and nothing is typed into any terminal. Closing the tab ends what runs in it, as the user's
  Close Tab does.
- Does it change or destroy what the phone does not own? It reaches only a terminal of a local workspace that the
  host itself lists, found by the pair of `workspace_id` and `terminal_id`; any other pair is `not_found`, and
  nothing closes. A terminal of another workspace, a tab that is gone, and every tab of an SSH or other remote
  workspace (never listed) are all `not_found`. Unlike `agent.close` it makes no live-agent check, by design: the
  user picked this tab in the list, so the shell fall-through rule above does not apply to it, and it closes a
  tab whether an agent, a shell or another program runs there. The Mac does not ask again: a phone is expected to
  have asked its user. On the workspace's last tab the Mac closes the workspace, as its Close Tab does by default;
  with its "Keep Workspace Open When Closing Last Surface" preference on it answers `refused` and closes
  nothing. The Mac's rules for closing a workspace still hold (a pinned workspace, the last workspace of a
  window): the answer is `refused`. While device management (MDM) blocks remote control the answer is `refused`
  and nothing is looked up or closed.
- Does it read state the phone has no business seeing? No. The answer is an `outcome` and nothing else, and the
  host never logs a workspace id, a terminal id or a title for it.

More rules: a Mac whose device management (MDM) blocks remote control does not run a Link host at all, and a
host that sees that policy change during a session answers every `workspace.create`, `workspace.rename`,
`workspace.close`, `agent.close` and `terminal.close` with `refused` without acting. Removing a phone on the Mac
closes its sessions at once (above). A control call, `agent.close` and `terminal.close` included, runs on its own,
so a slow Mac does not hold up the session's other calls. The host never logs a workspace title, directory, branch or tab title, nor the
title of an agent session. These are ShellX Link calls, not cmux socket methods: the allowlist of the `cmux ssh`
relay does not change.

**Why the rest is acceptable.** A paired phone is trusted like the user sitting at the Mac: it is signed in
to the user's account, and the user allowed that phone on that Mac in person; the relay can neither create
that trust nor widen it (section 9). Removing the phone on the Mac untrusts its key at once: its live
sessions close and its next handshake is refused. Removing it on the phone deletes the grant, so the relay
mints it no new connect ticket, and the Mac drops the key when it next checks the grants. Within that
trust, typing into the user's own agent session, stopping it, closing its terminal or any of its tabs, answering
its requests, and making, renaming and closing its workspaces are what the user could do at the keyboard; the
allowed calls limit *which objects* a phone reaches (this Mac's live agent sessions and their pending requests,
and its local workspaces with their terminal tabs), not what the user may do with them. Out of reach for a phone
in this version: spawning or respawning terminals (a new workspace's first terminal apart), keys or text for anything but a live agent,
opening URLs or files, the Mac's settings, the `bypass` modes, other machines and other accounts. The host
never logs message text, attachment names or bytes, tool inputs, workspace or tab names, keys, tickets or
tokens.
