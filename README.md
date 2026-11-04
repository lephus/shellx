<div align="center">

# ShellX

**Your terminal, on your phone. Run Claude Code, Codex, tmux and SSH sessions on your computer — and control them from iOS or Android, anywhere.**

End-to-end encrypted (Noise protocol) · No open ports · No static IP · No VPN · Free & open source (GPL-3.0)

[Website](https://shellx.pro) · [Guides](https://shellx.pro/guides/) · [Download](https://shellx.pro/#download) · [Discord](https://discord.gg/Wg69bq7Pu) · [Contributing](CONTRIBUTING.md)

</div>

---

## What is ShellX?

ShellX is a native terminal app for **macOS and Windows** plus a **phone app for iOS and Android**. The phone shows the terminal sessions that are *already running* on your computer, so you can:

- **Watch and answer Claude Code, Codex CLI, Gemini CLI or Aider from your phone** while the agent keeps working on your machine.
- **Get a push notification** when a long command finishes or a program waits for input.
- **Reach your Mac or PC terminal from anywhere** — behind NAT, CGNAT, hotel Wi-Fi or a company network — without port forwarding, dynamic DNS or a VPN.
- **Attach to tmux** and SSH workspaces you started on the desktop.

Both apps dial *out* to the ShellX relay. The relay only forwards encrypted frames and cannot read your terminal.

## Why not just SSH from my phone?

| | Mobile SSH client (Termius, Blink, JuiceSSH…) | ShellX |
|---|---|---|
| Needs an open port / public IP / VPN on your computer | Usually yes | **No** |
| Shows sessions already running on your desktop | Only via tmux, set up by you | **Yes, built in** |
| Push notification when a command finishes or an AI agent needs you | No | **Yes** |
| Works behind CGNAT / corporate NAT | Needs Tailscale or similar | **Yes** |
| Pairing | Keys + host config | **Scan a QR code** |
| Price | Free tier / subscription | **Free** |

Longer comparisons: [ShellX vs Termius](https://shellx.pro/guides/shellx-vs-termius/) · [ShellX vs Tailscale](https://shellx.pro/guides/shellx-vs-tailscale/) · [ShellX vs Claude Code Remote Control](https://shellx.pro/guides/claude-code-remote-control-vs-shellx/)

## Features

- **Desktop terminal** — workspaces, split panes, session restore, command palette, SSH workspaces, tmux attach. Built on [cmux](https://github.com/manaflow-ai/cmux) and the Ghostty terminal core.
- **Phone app** — live view of your desktop terminal sessions, type and answer prompts, switch between many sessions.
- **Noise-protocol end-to-end encryption** — keys stay on your devices.
- **No inbound connections** — nothing to expose, nothing to firewall.
- **QR pairing** — pair a phone in seconds.
- **Notifications** — know when a build, test run or AI agent needs you.

## Quick start

1. Install ShellX on your Mac or Windows PC from [shellx.pro](https://shellx.pro/#download).
2. Install the phone app (iOS / Android).
3. Scan the QR code shown on the desktop. Done — your sessions appear on the phone.

Step-by-step guides:
- [Use Claude Code on your phone](https://shellx.pro/guides/claude-code-on-phone/)
- [SSH from your phone without opening ports](https://shellx.pro/guides/ssh-from-phone/)
- [Remote terminal without a VPN](https://shellx.pro/guides/remote-terminal-without-vpn/)

## Contributing

ShellX is open source and we are looking for contributors — Swift/macOS, Rust, Windows, Node (relay) and Astro (website). Good first issues are labelled [`good first issue`](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22). See [CONTRIBUTING.md](CONTRIBUTING.md).

If ShellX is useful to you, a ⭐ helps other developers find it.

---

## For maintainers

ShellX is built on [cmux](https://github.com/manaflow-ai/cmux) by Manaflow: the macOS app is cmux with ShellX changes, and the Windows app is built on `cmux-tui`.

## Layout

- cmux tree (repo root: `Sources/`, `Packages/`, `cmux-tui/`, `ghostty` …): the macOS app and the Rust terminal core. ShellX code lives in `Packages/Shared/ShellXBrand`, `Sources/ShellX/`, `shellx-core/` and `windows/` so cmux updates merge cleanly.
- `relay/`: the ShellX API and relay (Node 22, Hono, SQLite), served at `relay.shellx.pro`.
- `web/`: the shellx.pro website (Astro).
- `deploy/`: VPS deployment (Docker behind nginx-proxy).
- `docs/superpowers/`: specs, plans and the ledger. The native rewrite starts at `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md`.

The previous Flutter apps (desktop and mobile 1.0.0) are kept at tag `flutter-final`.

## Updating from cmux

```bash
git remote add upstream https://github.com/manaflow-ai/cmux.git   # once
git fetch upstream && git merge upstream/main
```

Keep these deleted when merging (Business Source License or Manaflow-hosted services, never used by ShellX): `web/` from cmux (ShellX's own `web/` stays), `workers/` except `workers/cmux-paste-text/` (the app bundles it), `services/iroh-relay-minter/`, `cmux-tui/relays/cloudflare-do/`, and cmux's `.github/`.

## License

GPL-3.0-or-later, see `LICENSE` (cmux's license, kept as is) and `THIRD_PARTY_LICENSES.md`. ShellX is not affiliated with Manaflow.
