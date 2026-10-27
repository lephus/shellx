# shellx-link

ShellX Link is the phone-to-Mac protocol for ShellX: Noise sessions, a message codec, a relay client and sessions. It is a standalone Swift package that the ShellX Mac app and the future iOS app both use.

It is MIT licensed (see `LICENSE`), unlike the rest of this repository. For that reason it must not depend on, link to or copy code from GPL parts of the repo (`Sources/`, `ios/`, `Packages/`, `cmux-tui/`). Reading them to understand a protocol is fine. `scripts/shellx/check-link-license.sh` enforces the boundary.

## shellx-link-probe

`shellx-link-probe` plays a paired phone from a Mac terminal, for end-to-end checks and latency
measurements against a ShellX Mac (local relays or production). It signs in as a `mobile` device,
pairs from the Mac's QR offer and mints its own connect tickets, as the iOS app does.

```bash
swift build --package-path shellx-link
probe=shellx-link/.build/debug/shellx-link-probe
state=/private/tmp/phone-state   # outside any repository; created 0700

install -m 600 /dev/null pw.txt   # then write the password into it with an editor
$probe login --state $state --api https://relay.shellx.pro --email you@example.com --password-stdin < pw.txt
# On the Mac: right-click "This Mac" > "Pair iPhone…", or in a DEBUG build. The probe refuses an offer
# file others can read, so create it with umask 077 (a plain redirect makes it 0644):
#   (umask 077; CMUX_TAG=<tag> scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_offer '{}' > offer.txt)
$probe pair --state $state --offer-file offer.txt   # prints the pairing id; press Allow on the Mac
#   DEBUG: CMUX_TAG=<tag> scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_approve '{"pairing_id":"<id>"}'
$probe machines --state $state
$probe watch --state $state [--seconds 600] [--recheck]
$probe sessions --state $state
$probe approve <request_id> --state $state [--mode once|always|all|deny]
$probe answer <request_id> --state $state --select "<label or free text>" [--select ...]
$probe plan <request_id> --state $state --mode manual|auto_accept|ultraplan|deny [--feedback-file <file>]
$probe chat-history <session_id> --state $state [--limit 20] [--before <seq>]
$probe chat-send <session_id> --state $state --text-file message.txt
$probe chat-stop <session_id> --state $state [--hard]
$probe bench --state $state --count 50 --socket /tmp/shellx-debug-<tag>.sock
$probe unpair --state $state --machine <machine_id>
$probe logout --state $state
```

- `--state` holds `phone.key` (the Link static key), `session.json` (the relay token) and
  `machines.json` (paired machines with the host key from the QR), all 0600. The probe never prints
  the password, the token, a ticket, the private key or the offer's pairing code.
- `--machine <id>` picks the machine when more than one is paired.
- `answer` takes one `--select` per question, in order. An option's label picks that option; any
  other text is a free-text answer. Join the labels of a multi-select question with `", "`.
- `plan` with a non-empty `--feedback-file` asks Claude Code to revise the plan, whatever `--mode`
  says: the Mac answers the hook with "rejected, wants this change".
- `watch` exits 4 when the Mac or the relay ends the session, and 0 when `--seconds` pass. With
  `--recheck` it then tries to connect again twice: with a ticket minted before the end (only the
  Mac's trust check can refuse it) and with a new ticket (the relay's grant check).
- `bench` sends fake blocking Claude `PermissionRequest` hooks to the Mac app's control socket and
  answers them from the phone side. The app must accept other processes: a DEBUG build launched
  with `CMUX_SOCKET_MODE=allowAll`.
