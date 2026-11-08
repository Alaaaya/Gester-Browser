# KAMUI — iOS 27.x sandbox escape + MobileGestalt editor

> *Kamui (神威) — the eye that phases matter into another dimension. Here one
> symlinked part directory makes `containermanagerd` issue a sandbox extension
> for a container that should be out of reach.*

**Open source, MIT licensed and free for everyone.** KAMUI is not limited to
testers, a private group or an allowlist. Anyone can use, study, modify,
redistribute and ship the MobileGestalt editor under the MIT license.

Supported: **iOS 27.0.1 – 27.2** (primary target 27.2 / 24B115).

This repository contains the escape engine, the **KAMUI** app source (internal
target `BQTool`) and the release IPA.

---

## 0. Who can use it

**Everyone.** There is no invitation, tester list, waitlist or account. Clone
the repository, build the app, install the IPA, fork it, publish your own
build — the MIT license allows all of it.

The MobileGestalt editor itself has no access check and no allowlist. On
**iOS 27.2** the primary class-7 path needs at least one
`com.apple.security.application-groups` entitlement in the running app. KAMUI
2.4.0 also offers an **opt-in class-2 parent fallback** (Settings → Class-2
fallback), which renames the app's own `Library` and may work without an app
group. It is off by default because some builds terminate the app when
`Library` is moved. If both paths fail, the log shows exactly which step the
sandbox denied. On some **27.0.x** builds the legacy class-13 traversal may
work without an app group.

---

## 1. What this is

KAMUI is a **partial sandbox escape**: a normally sandboxed app obtains a
read/write sandbox extension for a path outside its own containers. It is not
root, not a kernel exploit and not a full filesystem escape. It is exactly
enough to:

- read and write the live **MobileGestalt** cache
  (`systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`);
- install custom **PosterBoard** wallpapers (`.tendies` descriptors) into the
  three provider descriptor folders;
- read and write other **MCM containers** whose path is known (app data, app
  group, SystemGroup).

The included app is a full UIKit toolbox:

- **Gestalt** — Dynamic Island on/off, Dynamic Island model picker (14/15/16/
  17/18 experimental or custom subtype), version spoof, Apple Intelligence,
  Siri AI US region, AI device spoof, iPadOS mode, Security Research Device
  (ResearchFuse), Store Demo Mode, AOD, Boot Chime, Charge Limit, Tap to Wake,
  Stage Manager, Apple Pencil, Action Button, Collision SOS, Parallax off,
  full `CacheExtra` editor (add/edit/delete; String/Integer/Boolean/Data),
  apply/revert/respring, backup.
- **PosterBoard** — import `.tendies`, apply all, online wallpaper catalog
  (`SerStars/Nugget-Wallpapers`), reset, open PosterBoard, respring. Applies to
  both classic and modern Collections providers and writes the PosterBoard
  refresh marker to avoid gray posters.
- **Settings** — diagnostics, in-place/atomic write toggle, log viewer, a
  test-device banner: “This iPhone is provided specifically for testing” with
  an editable “Managed by group:” label, and an in-app language picker.
- **Languages** — English, Russian, Korean, Arabic, Turkish, Ukrainian and
  Vietnamese, with automatic RTL layout for Arabic.

---

## 2. The bug

### 2.1 Old `bad_query` is patched on 27.2

`bad_query` used `container_query_operation_set_part_domain` with `..`
traversal:

```objc
query_set_class(q, 13);
query_set_group_identifiers(q, xpc_string_create("systemgroup.com.apple.mobilegestaltcache"));
query_set_part(q, 3);                 // Library/Caches
query_set_part_domain(q, "../../../../../../../.." + path);
query_set_flags(q, 0x8100000000);
```

On 27.2:

- `MCMXPCMessageQuery` rejects a `SystemDataDomain` containing `..`
  (`Rejecting query with invalid partDomain`).
- `MCMFileManager realPathForURL:ifChildOfURL:` resolves symlinks and rejects
  absolute/outside targets when `partDomain` is non-empty.
- A direct class-13 query returns the MG path but **no sandbox token** for an
  app without the matching entitlement.

### 2.2 The part-directory symlink

The fix validates `partDomain`, but **not the part directory itself** when the
domain is empty:

1. The app-group container is writable. Replace
   `<app group>/Library/Caches` with a symlink to the target container.
2. Query MCM:
   - class **7** (app group),
   - own group identifier,
   - part **3** (`Library/Caches`),
   - **empty** `partDomain`,
   - flags `0x8100000000` (include path + extension type 3).
3. `containermanagerd` builds `<app group>/Library/Caches`, sees a symlink, and
   issues the sandbox extension for the **resolved target**.
4. `sandbox_extension_consume` grants read/write to the target.

No traversal string is involved, so the 27.2 checks never see `..` and never
get a non-empty `partDomain` to validate.

The symlink is removed and the original `Library/Caches` restored after each
operation. Crashes are recovered on the next run (`Caches.bqtool` backup).

### 2.3 Class 2: part directories vs. the parent fallback

On iOS 27.2 the sandbox denies `rename()` of every class-2 part directory from
inside the app:

```
Library/Preferences  -> EPERM (errno 1)
Library/Caches       -> EPERM (errno 1)
Documents            -> EPERM (errno 1)
tmp                  -> EPERM (errno 1)
SystemData           -> EPERM (errno 1)
```

Only the app-group part directory is directly renameable. KAMUI 2.4.0 has an
**opt-in class-2 parent fallback** for builds without an app group. It is off
by default (2.2 ran it automatically and could crash on builds that kill the
process for moving `Library`):

1. Rename the app's own `Library` to `Library.bqtool`.
2. Create a small fresh `Library` and symlink `Library/Caches` to the target.
3. Query class 2 (own bundle identifier, part 3, empty `partDomain`,
   flags `0x8100000000`).
4. Restore the original `Library` immediately; the consumed token remains
   valid for the resolved target.

Enable it in **Settings → Class-2 fallback (experimental)** and then retry
Gestalt/PosterBoard. If the app closes when it is enabled, relaunch, disable the
switch, and send `Documents/bqtool.log`. If the sandbox denies moving
`Library`, the log shows `class2-parent: move Library -> bak failed` and the
class-7 path still needs an app group.

### 2.4 Dynamic app group

Old builds hardcoded one group. KAMUI reads the app's own runtime entitlements:

```objc
SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
CFTypeRef groups = SecTaskCopyValueForEntitlement(
    task, CFSTR("com.apple.security.application-groups"), NULL);
```

It picks the first group that yields a
`containerURLForSecurityApplicationGroupIdentifier` container. The MCM query
uses that group identifier. A build with **any** app group works; there is no
hardcoded identifier.

### 2.5 Multi-strategy escape (27.0.1–27.2)

`BQEscape` tries, in order, and logs every attempt:

| # | Strategy | Needs app group | Likely versions |
|---|---|---|---|
| 1 | class 13 + `partDomain` traversal (old `bad_query`) | no | 27.0.x where traversal is still open |
| 2 | class 7 part-directory symlink | yes | 27.2 |
| 3 | class 2 parent `Library` symlink (2.4.0, opt-in) | no | 27.2 if `Library` rename is allowed |
| 4 | class 13 direct MG query | no | builds that issue a token |
| 5 | class 12 geod + traversal | no | older builds |

The first successful strategy is used. A result but no token is logged as
`token=NO consume=-5` (`-5` is the app's "no token / consume failed", not an
installation error).

---

## 3. Reachable targets

Confirmed on 27.2 (redacted):

- **MobileGestalt** — 10 740-byte binary plist, parsed as `__NSDictionaryI`,
  79→80 `CacheExtra` keys, opened `O_RDWR`, marker written.
- **PosterBoard** — app data container
  `/var/mobile/Containers/Data/Application/<UUID>`; all three descriptor
  folders writable:
  - `com.apple.WallpaperKit.CollectionsPoster/descriptors`
  - `com.apple.MercuryPoster/descriptors`
  - `com.apple.PhotosUIPrivate.PhotosPosterProvider/descriptors`
- **App data containers** — 245 containers enumerated with `fsgetpath` and
  opened with tokens.
- **PosterBoard `.tendies` pipeline** — 25-file ZIP extracted, descriptor
  found, IDs randomized, folder written to the WallpaperKit provider.

The same technique can reach other MCM containers whose path is known.

---

## 4. Build

Requirements: Linux/macOS, clang, an iOS SDK (Theos SDK works), zlib.

```bash
./build.sh
# -> build/KAMUI-2.4.0.ipa
```

The default bundle identifier is `com.kamui.escape`. Override with `BID=...`.
The SDK path can be overridden with `SDK=...`.

---

## 5. Install and runtime requirement

Anyone can install `KAMUI-2.4.0.ipa`; use whatever installation method you
normally use.

The primary 27.2 strategy needs the running app to have at least one
`com.apple.security.application-groups` entitlement. KAMUI reads its own
entitlements at runtime and uses the first group that has a container URL.

- **With an app group** — class 7 is attempted after the class-13 fallback and
  is the working path on 27.2.
- **Without an app group** — the app logs `(none)` and tries the legacy
  class-13 traversal. That may work on some 27.0.x builds; it is closed on
  27.2.

There is no hardcoded group identifier, so any build that grants an app group
can use the primary path.

---

## 6. Usage

On first launch:

- Gestalt loads the live MG plist and creates
  `Documents/OriginalGestalt.plist` (true original) if missing.
- Apply writes the plist (in-place with rollback, or atomic), verifies it and
  offers a respring.
- Revert restores the backup.
- PosterBoard → Import `.tendies` / Explore Wallpapers → Apply → Open
  PosterBoard / Respring.

**Keep `OriginalGestalt.plist`.** If the app is deleted, the backup goes with
it.

---

## 7. Logs and diagnostics

- `Documents/bqtool.log` — session log (iOS build, group identifier, every
  strategy, MG reads/writes, ZIP/descriptor apply).
- Settings → Run Diagnostics — MG read/write check + PosterBoard container
  search.
- Settings → Open Log — viewer with refresh/clear.

If an escape fails, the first lines show which strategy failed and why:

```
strategy class13-traversal: ... result=0x0 token=NO consume=-5
strategy class7-symlink: ... result=0x... token=YES consume=3
escape: using class7 symlink
```

---

## 8. Version notes

- **2.4.0** — adds Russian, Korean, Arabic, Turkish, Ukrainian and Vietnamese
  localization with an in-app language picker; adds the class-2 subpath token
  probe and iterates all app groups; fixes `.tendies` installation by writing
  both Collections providers and the PosterBoard refresh marker.
- **2.3.1** — crash-guard hotfix: the class-2 fallback is opt-in and is
  automatically disabled after an unfinished attempt. 2.2 ran it
  automatically and could terminate the app when `Library` was moved.
- **2.2** — added the class-2 parent fallback,
  Dynamic Island enable/disable and model picker, version spoof, Apple
  Intelligence, Siri AI US region, AI device spoof, iPadOS mode, ResearchFuse
  (Security Research Device), Store Demo Mode, and the in-app test-device /
  “Managed by group” banner.
- **27.2 (24B115)** — primary, tested: class-13 traversal closed; class-7
  part-directory symlink works.
- **27.0.1 / 27.1** — the class-13 traversal or class-12 geod fallback may
  still work, possibly without an app group. If all strategies return `-5`,
  send `Documents/bqtool.log`; the log distinguishes an entitlement problem
  from a build-specific MCM change.
- The app is built with the iOS 14.5 SDK and runs on 27.x.

### Diagnostic notes

For each device/build send the first 15–20 lines of `Documents/bqtool.log`:

```
=== BQEscape start | iOS <build> | bundle ...
app group entitlement: <group or (none)>
strategy class13-traversal: result=... token=... consume=...
strategy class7-symlink: result=... token=... consume=...
strategy class2-parent: result=... token=... consume=...
escape: using ...
```

This distinguishes:

- no app group + traversal closed → entitlement/installation limitation;
- app group present + class 7 neither result nor token → version-specific MCM
  change;
- result but no token → entitlement or target-path issue;
- token but consume fails → kernel/extension mismatch.

---

## 9. Limitations and safety

- No root, no kernel, no arbitrary `/var` access. Only MCM containers (or
  paths reachable through the legacy traversal on vulnerable builds).
- POSIX DAC still applies; write only where user `mobile` can write.
- MobileGestalt edits can break features or soft-brick the device. Keep the
  backup. Do not apply unknown keys.
- iPadOS mode, Apple Intelligence/Siri spoofing, ResearchFuse, Store Demo Mode
  and version spoofing are behind confirmation prompts for a reason. iPadOS
  mode patches the binary `CacheData` blob; AI/Siri spoofing can break Face ID;
  version spoofing can break OTA updates. Revert if anything misbehaves.
- PosterBoard Reset removes **all** descriptors from the three provider
  folders, including stock collections; PosterBoard normally regenerates stock
  ones.
- Use it only on devices you own or have permission to modify.

---

## 10. Disclosure and public use

KAMUI is public, MIT-licensed research. The primitive and the MobileGestalt
editor are available to everyone; there is no embargo, tester list or private
group.

- If you find a bug in KAMUI, open a GitHub issue or security advisory.
- If you want to report the underlying MCM behavior to Apple, use **Apple
  Security Bounty** (Sandbox Escape category) and include the iOS build, the
  exact query (class 7 / part 3 / empty `partDomain` / flags `0x8100000000`),
  the symlinked part-directory behavior, and a video/log of MobileGestalt
  write + PosterBoard descriptor write.
- Suggested fix direction: canonicalize and validate the **part directory**
  against the container for every part, and reject symlinked part directories
  regardless of `partDomain`. The current checks cover `partDomain` but not the
  part path itself.

See [SECURITY.md](SECURITY.md).

---

## 11. Credits

- KAMUI primitive, app, dynamic group and multi-strategy: this project.
- `bad_query` research: forcequitOS, 0xjohnny.
- UI/feature inspiration: rooootdev/mond.
- NeoSpring respring: neonmodder123, skadz108.
- Wallpaper catalog: SerStars/Nugget-Wallpapers.
- Theos tooling.

---

## 12. License and release assets

KAMUI is released under the **MIT License** — see [LICENSE](LICENSE). You may
use, copy, modify, merge, publish, distribute, sublicense and sell copies of
the software, including the MobileGestalt editor, as long as the copyright and
permission notice are preserved.

`v2.4.0`:

- `KAMUI-2.4.0.ipa` — the app; install it on any supported device.
- Source code and build script are in this repository.

There is no allowlist and no special access. The anime name is for fun; the
code is serious.
