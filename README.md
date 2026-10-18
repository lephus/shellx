# ShellX

ShellX is a native terminal app for macOS and Windows with remote access from your other machines and your phone. It is built on [cmux](https://github.com/manaflow-ai/cmux) by Manaflow: the macOS app is cmux with ShellX changes, and the Windows app is built on `cmux-tui`.

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
