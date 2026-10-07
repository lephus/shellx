---
layout: ../../../layouts/Guide.astro
lang: en
slug: ssh-from-phone
order: 2
title: "SSH from your phone without opening ports"
metaTitle: "SSH from your phone without opening ports — ShellX guide"
description: "The classic ways to SSH from a phone, what they need (open ports, static IP, VPN), and how ShellX puts your SSH and tmux sessions on the phone with none of that."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["SSH from phone", "SSH from iPhone", "SSH from Android", "mobile SSH without port forwarding", "tmux on phone", "SSH client alternative"]
---

Wanting a shell on your phone usually means one of two things: reaching a **server** (a VPS, a dev box, a Raspberry Pi), or reaching your **own computer** to check on something running there. This guide covers both, and shows where ShellX fits.

## The classic way: a mobile SSH client

A mobile SSH client connects straight to an SSH server. For that to work, the server has to accept an incoming connection from wherever your phone is:

- **A public server** (a cloud VPS) already has a public IP and port 22 open. A mobile SSH client is the simplest choice here.
- **A machine at home or in the office** sits behind a router, often behind CGNAT, with no public IP. You need port forwarding on the router, a dynamic DNS name, or a VPN such as WireGuard or Tailscale.
- **Your own Mac or PC** also needs its SSH server turned on (Remote Login on macOS, OpenSSH Server on Windows), and you get a **new** shell, not the terminal windows you already have open, unless everything runs inside `tmux`.

Typing on a phone in a raw SSH session is also rough when the connection drops: the session is gone unless you use `tmux` or `mosh`.

## The ShellX way: open the sessions already running on your computer

ShellX starts from your computer instead of the server:

1. **Install ShellX on your Mac or PC** and create an account.
2. **Install the phone app**, sign in, and pair it by scanning the QR code from the tray menu on your computer.
3. **SSH from the ShellX app on the computer as usual.** Run `ssh my-server` in any tab, or press **⌘⇧K** (Windows **Ctrl+Shift+K**) and pick a host from your `~/.ssh/config`. ShellX opens an SSH workspace for it.
4. **Open the session on your phone.** The phone sees every pane, SSH panes included, and shows the remote folder as `host:/path`.

Because both the computer and the phone **dial out** to the ShellX relay, nothing on your network accepts incoming connections: no port forwarding, no static IP, no VPN.

### What the SSH workspace adds

- **Your own `ssh` and SSH agent.** ShellX runs the operating system `ssh` binary with your keys and `~/.ssh/config`. It never asks for, keeps or stores passwords; a password or host-key prompt appears inside the terminal, like in any terminal.
- **Automatic reconnect.** If the network drops, the pane shows that it lost the connection and reconnects by itself, in the same place in your layout.
- **tmux attach.** List the `tmux` sessions on your computer or on the server and attach one as a tab. Programs inside tmux keep running when you disconnect.
- **Remote context.** The sidebar shows the server's current folder, branch and listening ports; a click opens a forwarded port in your browser.
- **Nothing to install on the server.** No agent or daemon runs there; ShellX only places a small shell hook in the server's cache folder for the folder and branch display.

## Which one should you use?

| Situation | Best fit |
|---|---|
| Quick access to a public VPS from a phone, no computer involved | A mobile SSH client |
| Your computer at home or work, behind NAT, no VPN | ShellX |
| Following long jobs or AI agents already running in your terminal | ShellX |
| Push notification when a command finishes | ShellX |
| Many servers, already reachable over a VPN | Either; ShellX adds the session-on-phone and notifications |

## Security

The phone and the computer agree on keys during QR pairing, and all terminal content is end-to-end encrypted with the Noise protocol. The relay only forwards encrypted frames. Your SSH keys stay in your SSH agent on the computer; they never go to the phone or the relay.

## FAQ

**Is ShellX a replacement for my SSH client?** For reaching your own computer and the servers you already work on from it, yes. If you want to connect from the phone to a server without any computer in between, a mobile SSH client is still the direct route.

**Does it work on Linux?** The ShellX desktop app runs on macOS and Windows. From there you can SSH into Linux servers as usual.

**Does it cost anything?** ShellX is currently free.
