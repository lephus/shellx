---
layout: ../../layouts/Guide.astro
lang: en
slug: ai-coding-agent-on-phone
order: 7
title: "Run Codex CLI, Gemini CLI or Aider from your phone"
metaTitle: "Use Codex CLI, Gemini CLI & Aider from your phone — ShellX"
description: "Keep Codex CLI, Gemini CLI, Aider or Claude Code running on your computer and approve prompts from your iPhone or Android. No open ports, no VPN. Free."
published: "2026-11-03"
updated: "2026-11-03"
keywords: ["Codex CLI on phone", "Gemini CLI mobile", "Aider on phone", "AI coding agent mobile", "approve agent prompts from phone", "monitor AI agent from phone"]
---

CLI coding agents work best on your own computer: your repo, your toolchain, your secrets, your GPU. The problem is they keep stopping to ask *"Allow this command?"* — and you're not at your desk.

ShellX fixes that: the agent keeps running in a terminal on your Mac or Windows PC, and your phone shows the same terminal, end-to-end encrypted, with a push notification when the agent needs you.

**Works with:** OpenAI Codex CLI, Google Gemini CLI, Claude Code, Aider, OpenCode, Cursor CLI, Goose, Amp — anything that runs in a terminal.

## What you need

- ShellX desktop on macOS or Windows — [download](https://shellx.pro/#download)
- The ShellX phone app (iOS / Android)
- Your agent installed as usual (`npm i -g @openai/codex`, `npm i -g @google/gemini-cli`, `pip install aider-chat`, …)

## Step by step

1. **Pair your phone.** Open ShellX on the desktop and scan the QR code with the phone app.
2. **Start the agent in a ShellX tab.**
   ```bash
   cd ~/code/my-app
   codex        # or: gemini, aider, claude, opencode
   ```
3. **Give it a long task**, e.g. *"migrate the tests to Vitest and fix failures"*, then leave.
4. **Get notified.** When the agent stops for approval or finishes, ShellX sends a push notification.
5. **Answer from your phone.** Open the session, read the diff or the question, type `y`, a follow-up prompt, or `Ctrl-C`.

### Tip: one pane per agent

Run two agents side by side — e.g. Codex on a refactor and Gemini CLI writing docs — in split panes. The phone app lists every session, so you can jump between them.

### Tip: keep the computer awake

The agent runs on your computer. On macOS use `caffeinate -dimsu` in another tab; on Windows set *Sleep: Never* while plugged in.

## Why not SSH from the phone?

You can — but you'd need an open port or a VPN, and you'd start a *new* shell, not see the agent that's already running. ShellX attaches to the existing session, works behind NAT/CGNAT, and needs no server config. More: [SSH from your phone without opening ports](/guides/ssh-from-phone/).

## Security

- End-to-end encrypted with the Noise protocol; the relay forwards encrypted frames only.
- No inbound connections to your computer.
- Your repo and secrets stay on your computer; only the terminal screen travels, encrypted.
- Open source: [github.com/lephus/shellx](https://github.com/lephus/shellx).

## FAQ

**Can I use Codex CLI on my iPhone?** Codex CLI doesn't run on iOS, but with ShellX it runs on your computer and you control it from your iPhone.

**Does Gemini CLI have a mobile app?** Not a terminal one. ShellX gives you mobile access to a Gemini CLI session running on your desktop.

**Is this different from Claude Code Remote Control?** Remote Control only covers Claude Code. ShellX covers every terminal program. See [Claude Code Remote Control vs ShellX](/guides/claude-code-remote-control-vs-shellx/).

**Is ShellX free?** Yes, ShellX is currently free.
