# KAMUI 2.3 — iOS 27.0.1–27.2 sandbox escape + MobileGestalt editor

**Open source, MIT licensed and free for everyone.** There is no tester list,
private group or allowlist. Anyone can use, modify and redistribute KAMUI and
the MobileGestalt editor.

## Assets

- `KAMUI-2.3.ipa` — the app. Install it on any supported device.
- Source code and build instructions are in the repository.

## 2.3 hotfix

2.2 ran the class-2 parent fallback automatically. On builds that terminate
the app when its own `Library` is moved, that looked like a launch crash. In
2.3 the fallback is **off by default** and available in
**Settings → Class-2 fallback (experimental)**. With it off, the app launches
normally on every build; with it on, the log records `class2-parent` and the
result.

If KAMUI closes when you enable the switch, relaunch, disable the switch and
send `Documents/bqtool.log`. Do not enable it if you already have an app group.

## What's new since 2.1

- **Dynamic Island controls**: enable/disable, model/position picker for
  iPhone 14/15/16/17/18 (experimental) and a custom subtype field.
- **Version spoof**: writes ProductVersion and BuildVersion into MobileGestalt.
- **Apple Intelligence / Siri AI**: capability key, US region, and AI device
  spoof (iPhone 15 Pro / 15 Pro Max / 16 Pro / 16 Pro Max).
- **iPadOS mode**: five Medusa keys plus the binary CacheData patch.
- **Security Research Device (ResearchFuse)** and **Store Demo Mode** toggles.
- **Test-device banner**: “This iPhone is provided specifically for testing”
  with an editable “Managed by group:” label in Settings.
- **Class-2 fallback** (opt-in) for devices without an app group.

## Runtime requirement

The primary 27.2 class-7 strategy needs at least one
`com.apple.security.application-groups` entitlement in the running app. If
there is none, enable the class-2 fallback in Settings and retry. If the
sandbox denies moving `Library`, the log says so and an app group is still
required for the class-7 path.

## Tested

iOS 27.2 (24B115): MG read/write, PosterBoard descriptors, `.tendies` pipeline,
live Dynamic Island. 27.0.1–27.2 use the same MCM query; open an issue with
`Documents/bqtool.log` if a strategy fails.

## Warnings

iPadOS mode, AI/Siri spoofing, ResearchFuse, Store Demo Mode and version
spoofing are high risk. They can break Face ID, layout, OTA updates or boot
behavior. Keep `OriginalGestalt.plist` and use Revert if anything misbehaves.

## License

MIT. Use it, fork it, ship it, sell it — keep the copyright and permission
notice. See `LICENSE`.

## Disclosure

KAMUI is public research. If you find a bug in the app, open an issue. If you
want to report the underlying MCM behavior to Apple, use Apple Security
Bounty. See `SECURITY.md`.
