# KAMUI 2.1 — iOS 27.0.1–27.2 sandbox escape + MobileGestalt editor

**Open source, MIT licensed and free for everyone.** There is no tester list,
private group or allowlist. Anyone can use, modify and redistribute KAMUI and
the MobileGestalt editor.

## Assets

- `KAMUI-2.1.ipa` — the app. Install it on any supported device.
- Source code and build instructions are in the repository.

## What's new in 2.1

- **Multi-strategy escape**: class13 traversal → class7 part-directory symlink
  → class13 direct → class12 geod traversal. Each attempt is logged with
  `result/token/consume`.
- **Dynamic app group**: reads the app's own runtime entitlements; no
  hardcoded group identifier.
- Gestalt editor, device subtype, PosterBoard `.tendies` import/apply, online
  wallpaper catalog, diagnostics, NeoSpring respring.

## Runtime requirement

The primary 27.2 strategy needs at least one
`com.apple.security.application-groups` entitlement in the running app. The app
finds it at runtime. Without one, it tries the legacy class-13 traversal, which
may work on some 27.0.x builds but is closed on 27.2.

## Tested

iOS 27.2 (24B115): MG read/write, PosterBoard descriptors, `.tendies` pipeline,
live Dynamic Island. 27.0.1–27.2 use the same MCM query; open an issue with
`Documents/bqtool.log` if a strategy fails.

## `-5` meaning

The MCM query returned a result but no sandbox token was issued, or `consume`
failed. It is not an installation error. The log shows which strategy reached
which stage.

## License

MIT. Use it, fork it, ship it, sell it — keep the copyright and permission
notice. See `LICENSE`.

## Disclosure

KAMUI is public research. If you find a bug in the app, open an issue. If you
want to report the underlying MCM behavior to Apple, use Apple Security
Bounty. See `SECURITY.md`.
