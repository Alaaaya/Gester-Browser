# Security policy — KAMUI

KAMUI is **public, MIT-licensed research software**. Anyone may use, study,
modify and redistribute it, including the MobileGestalt editor. There is no
private group, tester list or embargo.

## Scope

- iOS 27.0.1 – 27.2, on devices you own or have permission to modify.
- Target: MobileContainerManager / `containermanagerd` sandbox extension
  issuance (partial sandbox escape).
- Out of scope: attacking third-party devices, malware, persistence, data
  exfiltration.

## Reporting

Bugs in KAMUI: open a GitHub issue or a security advisory in this repository.
Include:

- iOS build (e.g., 27.2 24B115);
- `Documents/bqtool.log` first 15–20 lines (contains no personal data);
- exact error text if the app does not install;
- whether the build has an app group and which strategy the log shows.

If you want to report the underlying MCM behavior to Apple, use **Apple
Security Bounty** (Sandbox Escape category). This project is public, so there
is no private disclosure window to coordinate.

## Safe handling

- Do not commit personal device data or backups to the repository.
- MobileGestalt edits can break features or soft-brick a device. Keep
  `OriginalGestalt.plist` and use Revert.
- Use the app only on devices you own or have permission to modify.
