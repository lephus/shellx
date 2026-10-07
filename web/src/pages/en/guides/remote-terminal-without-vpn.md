---
layout: ../../../layouts/Guide.astro
lang: en
slug: remote-terminal-without-vpn
order: 3
title: "Control your Mac or PC terminal remotely without a VPN"
metaTitle: "Remote Mac or PC terminal without a VPN — ShellX guide"
description: "Reach the terminal of your home or office computer from your phone behind NAT or CGNAT: no VPN, no port forwarding, no static IP, end-to-end encrypted."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["remote terminal without VPN", "access Mac terminal remotely", "remote terminal behind NAT", "no port forwarding", "CGNAT remote access", "control PC terminal from phone"]
---

You started a build, a data import or an AI agent on your computer, and now you are out. You want to look at that terminal from your phone. The usual answers are a VPN or port forwarding. Both work; both are more setup than the job deserves, and some networks make them impossible.

## Why remote access is usually hard

Home and office computers almost never have a public address:

- **The router hides them (NAT).** To reach a computer from outside, you forward a port on the router to it. That needs access to the router, and it exposes a service to the whole Internet.
- **Many ISPs and mobile networks use CGNAT.** Your router itself has no public IP, so port forwarding is not possible at all.
- **Office networks** rarely let you forward anything.
- **A VPN** (WireGuard, OpenVPN or a mesh VPN like Tailscale) solves reachability, but you still need an SSH server on the computer and a way to get back to the terminal windows you already have open.

## How ShellX avoids all of it

ShellX turns the connection around. The ShellX app on your computer and the app on your phone each **dial out** to the ShellX relay over the Internet, the same way a browser opens a website. Outgoing connections work behind NAT, CGNAT and most office networks, so:

- **No port forwarding** and nothing listening for incoming connections on your computer.
- **No static IP** or dynamic DNS.
- **No VPN client** on the phone or the computer.

The relay only matches your two devices and forwards their traffic. It cannot read it: terminal content is **end-to-end encrypted** with the Noise protocol, with keys agreed when you pair the phone by QR code.

## Set it up in three steps

1. **Install ShellX on the computer** (macOS 12+ or Windows 10 1809+) and create an account.
2. **Install the phone app** (iOS 15+ or Android 8.0+) and sign in with the same account.
3. **Pair them.** Open the tray menu on the computer, choose to pair a phone, and scan the QR code.

From now on, every terminal session in ShellX on your computer can be opened from your phone, from anywhere with an Internet connection.

## Day-to-day use

- **Many sessions at once.** Switch between tabs and panes on the phone as if you were at the machine.
- **Spotty mobile data is fine.** The computer keeps the latest 256 KiB of each session's output; when the phone reconnects, what happened in between is replayed.
- **Notifications.** Get a push when a long command finishes, or when a program or script asks for you (`shellx notify "done"`, or OSC 9 / 777 / 99 sequences).
- **Servers too.** SSH workspaces and `tmux` sessions you open in the ShellX app on the computer show up on the phone like any other session.

## When a VPN is still the right tool

ShellX is about **terminals**. If you need file shares, remote desktop, databases or every port of a machine, a VPN gives you the whole network. The two combine well: keep your VPN for network access and use ShellX to follow terminal sessions from your phone with notifications. See [ShellX vs Tailscale](/en/guides/shellx-vs-tailscale/).

## FAQ

**Does my computer have to stay awake?** Yes. The sessions run on it, so it must be on and connected. If it sleeps, the phone reconnects when it wakes up.

**Is anything stored on ShellX servers?** Only your account, device and pairing records, and the push token of phones that allowed notifications. Terminal content is end-to-end encrypted and cannot be read or stored. Details are in the [privacy policy](/en/privacy/).

**Does it cost anything?** ShellX is currently free.
