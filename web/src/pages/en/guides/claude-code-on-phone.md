---
layout: ../../../layouts/Guide.astro
lang: en
slug: claude-code-on-phone
order: 1
title: "How to use Claude Code and Codex from your phone"
metaTitle: "Claude Code and Codex from your phone — ShellX guide"
description: "Run Claude Code, Codex or any CLI coding agent on your computer and follow it from your phone: answer prompts, review changes, get a push when it needs you."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["Claude Code on phone", "Claude Code mobile", "Codex CLI from phone", "AI coding agent remote", "control Claude Code from iPhone", "Claude Code Android"]
---

AI coding agents such as **Claude Code** and **Codex** work best in a terminal on your own computer: they see your repository, run your tests and use your tools. The catch is that they often run for minutes, then stop to ask a question or wait for approval. If you have stepped away from your desk, the agent sits idle until you come back.

ShellX fixes that. The agent keeps running on your Mac or PC, and you open **that same terminal session** on your phone to read what it is doing, answer it, and let it continue.

## What you need

- ShellX on your computer (macOS 12 or later, Windows 10 version 1809 or later).
- The ShellX app on your phone (iOS 15 or later, Android 8.0 or later), signed in with the same account and paired with a QR code.
- Claude Code, Codex or another command-line agent installed on the computer, as usual.

Nothing changes in how you install or log in to the agent. ShellX does not proxy the agent's API traffic; it only carries the terminal, end-to-end encrypted between your two devices.

## Step by step

1. **Start the agent in a ShellX terminal.** Open a tab in the ShellX app on your computer, `cd` into your project and run `claude` (or `codex`). Give it a task as you normally would.
2. **Open the session on your phone.** In the ShellX app on your phone, pick your computer, then the session. You see the same screen, live, and can type into it. Scrolling back works too, so you can read what happened while you were away.
3. **Answer and approve from anywhere.** When the agent asks "Do you want to make this edit?" or needs a clarification, type the answer on your phone. The agent continues on your computer immediately.
4. **Get notified instead of checking.** ShellX turns terminal notifications into push notifications on your phone. Any program that sends **OSC 9**, **OSC 777** or **OSC 99** notifications is covered. Claude Code lets you choose a terminal notification channel in its settings (`/config`); pick one that uses these sequences. From any script or hook you can also run:

```sh
shellx notify "Claude Code is waiting for you"
```

Inside a ShellX pane this shows up on the tab and as a push on your paired phone.

## Let the agent use ShellX too

ShellX ships a command-line tool, `shellx`, that agents can call: open a split for a dev server, wait for a line in its log, read a pane's output, send a notification. Install the ready-made skill so Claude Code knows how to use it:

```sh
shellx skills install --claude   # or --codex
```

After that the agent can, for example, start `npm run dev` in a side pane with `shellx split --right --cmd "npm run dev"` and wait for it with `shellx wait`, without stealing your focus.

## Why not just SSH into the computer?

You could enable SSH on your Mac, open a port or install a VPN, and attach to a `tmux` session from a mobile SSH client. That works, but it is several moving parts, and it gives you a **new** shell, not the window the agent is already running in unless you planned ahead with tmux. ShellX needs no open port and no VPN, shows the exact session that is already running, and adds push notifications. See [ShellX vs Termius](/en/guides/shellx-vs-termius/) and [ShellX vs Tailscale](/en/guides/shellx-vs-tailscale/) for the trade-offs.

## Security notes

- Terminal content is end-to-end encrypted with the Noise protocol. The relay in the middle only forwards encrypted frames and cannot read your code, prompts or output.
- Pairing uses a QR code shown on your computer; private keys never leave the device.
- If the phone loses its connection, the computer keeps the latest 256 KiB of each session's output and replays it when the phone reconnects.

## FAQ

**Does the agent run on my phone?** No. It runs on your computer, with your files, credentials and tools. The phone is only the screen and keyboard.

**Does this work with other agents?** Yes. Anything that runs in a terminal works the same way: Codex, Aider, Gemini CLI, or a long `npm test`.

**Does it cost anything?** ShellX is currently free.
