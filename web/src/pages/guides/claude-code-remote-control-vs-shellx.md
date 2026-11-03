---
layout: ../../layouts/Guide.astro
lang: en
slug: claude-code-remote-control-vs-shellx
order: 6
title: "Claude Code Remote Control vs ShellX: control AI coding agents from your phone"
metaTitle: "Claude Code Remote Control vs ShellX — which to use?"
description: "Claude Code Remote Control or ShellX? Compare setup, plans, supported agents (Codex, Gemini CLI), notifications and security on your phone."
published: "2026-11-03"
updated: "2026-11-03"
keywords: ["Claude Code Remote Control", "Claude Code Remote Control alternative", "Claude Code on phone", "Claude Code mobile", "control Claude Code from iPhone", "Codex CLI on phone"]
---

**Short answer:** if you only use Claude Code, have a Claude Pro or Max plan, and are happy approving each action in the Claude app, Anthropic's built-in **Remote Control** is the simplest choice. If you also run **Codex, Gemini CLI, Aider, builds, tests or tmux sessions**, want **one app for every terminal session**, or use an **API key / Team plan**, use **ShellX** — it mirrors the real terminal, not just the Claude conversation.

You can use both: they don't conflict.

## What each one is

**Claude Code Remote Control** (launched February 2026 as a research preview) lets you start `claude remote-control` (or `/rc` inside a session) and continue that Claude Code session from the Claude app on iOS/Android or from claude.ai/code. The session still runs on your computer; messages are routed through Anthropic's API.

**ShellX** is a free, open-source terminal for macOS and Windows plus a phone app. The phone shows *the terminal sessions already running on your computer* — Claude Code, any other CLI agent, a dev server, a long build — end-to-end encrypted with the Noise protocol, with no open ports and no VPN.

## Side-by-side

| | Claude Code Remote Control | ShellX |
|---|---|---|
| What you see on the phone | The Claude Code conversation | The full terminal session (any program) |
| Works with Codex CLI, Gemini CLI, Aider, OpenCode… | No — Claude Code only | Yes — anything that runs in a terminal |
| Works with plain shells, tmux, SSH, builds, tests | No | Yes |
| Account / plan | Claude Pro or Max at launch; API keys not supported at launch | Free, no Claude plan needed |
| What can notify you on the phone | Claude Code only | Any session: agent waiting, command finished, build failed |
| Network | Outbound HTTPS, no inbound ports | Outbound only, no inbound ports, works behind CGNAT |
| Encryption | TLS to Anthropic | End-to-end (Noise); relay can't read content |
| Multiple sessions on one phone | One remote session per Claude Code instance | Many sessions, switch between them |
| Open source | No | Yes (GPL-3.0) — [github.com/lephus/shellx](https://github.com/lephus/shellx) |
| Desktop OS | Wherever Claude Code runs | macOS, Windows |

*Remote Control details are from Anthropic's launch (Feb 2026) and may have changed — check Anthropic's docs for the current plan list.*

## When Remote Control is the better pick

- You use Claude Code and nothing else in the terminal.
- You like Claude's mobile UI for reading diffs and chatting with the agent.
- You don't want to install another desktop app.

## When ShellX is the better pick

- **You run more than one agent.** Claude Code in one pane, Codex or Gemini CLI in another, a test watcher in a third — ShellX shows all of them.
- **You need the raw terminal.** Interactive prompts, TUI programs, `git rebase -i`, `htop`, a REPL — Remote Control shows the conversation, ShellX shows the screen.
- **You're on an API key, Team or Enterprise plan** and Remote Control isn't available to you.
- **You want a notification for anything**, not only the agent: "build finished", "tests failed", "deploy waiting for confirmation".
- **You care about end-to-end encryption** and an auditable, open-source relay.

## Using Claude Code with ShellX in 3 steps

1. Install ShellX on your Mac or Windows PC and the phone app — [download](https://shellx.pro/#download).
2. Scan the QR code to pair your phone.
3. Run `claude` in a ShellX tab and walk away. Keep the computer awake; open the session on your phone whenever ShellX notifies you.

Full walkthrough: [How to use Claude Code on your phone](/guides/claude-code-on-phone/).

## FAQ

**Is ShellX an official Anthropic product?** No. ShellX is an independent open-source project. It works with Claude Code the same way it works with any terminal program.

**Can I use Remote Control and ShellX together?** Yes. Run Claude Code inside a ShellX tab and also enable `/rc` if you want — they don't interfere.

**Does ShellX send my code to a server?** Terminal frames go through the ShellX relay end-to-end encrypted; the relay cannot read them. Your code stays on your computer.

**Does my computer need to stay on?** Yes, for both tools. The agent runs on your computer; the phone is a remote screen and keyboard.

**Does ShellX work for Codex CLI or Gemini CLI on my phone?** Yes — see [Run any AI coding agent from your phone](/guides/ai-coding-agent-on-phone/).
