# Read-only browser baseline

Isolated branch based on upstream 7ed710ca6c4fb5bbf07729d96fddd2a622383d2f.
Existing toolbox functions remain untouched; the new Files tab is separate.
No GPL source or supplied IPA content was incorporated. Upstream MIT license remains intact.

The browser starts in its own app sandbox. Files picker explicitly grants additional locations.
No discovery of other apps, private container APIs, escape initialization, writable probes,
bookmark persistence, editor, archive extraction, export, rename, move or delete is added.
Existing toolbox tabs still have their original actions, including writing operations.
"Read only" describes the new browser, not the whole upstream application.

Directory list is capped at 2,000 entries and searches only those displayed names.
Navigation uses the native back stack plus a root-relative breadcrumb label.
Symlinks and special files are not previewed. Descriptor-relative traversal rejects parent,
absolute and empty path components, with O_NOFOLLOW at each step. Files are always opened
O_RDONLY. Security-scoped access lifetime is shared across child screens and released
when their location object is deallocated. Explicit provider selection uses coordinated reading.
Providers may download/materialize a selected document; this is not an offline guarantee.

Text is UTF-8 plain text, no WebView, no executable preview, no data detectors.
Read caps are 512 KiB for text/plist and 8 MiB for images, enforced during read as well as stat.
Plist display is an intentionally truncated structural summary, with 12 levels, 1,000 nodes
and bounded strings; not an editor or a lossless XML export.
Images are first-frame ImageIO thumbnails capped at 1,600 pixels, not full animated decoding.
Listing and preview work runs off the main queue. Arabic and English browser copy included,
with LTR navigation/list structure in either language.

Validation performed on Linux
- Native C access-policy tests compile with -Wall -Wextra -Werror and pass.
- Tests cover real fixture read, read-only descriptor, root dup, invalid descriptor,
  and nine traversal, missing path and symlink denial cases.
- build.sh passes bash syntax validation.
- Objective-C UIKit compilation NOT performed. No clang/Xcode/iOS SDK in this sandbox.
- build.sh attempted and stopped immediately at SDK discovery, before compilation.
- No new IPA exists; no artifact ZIP/metadata validation can honestly be claimed.
- No iPhone execution, signing, simulator testing, release or remote push performed.

Next build on an authorized macOS/Xcode machine without signing
xcodebuild -project Gester.xcodeproj -scheme Gester -configuration Release \
  -sdk iphoneos -derivedDataPath build-browser CODE_SIGNING_ALLOWED=NO build

Alternatively use project.yml with XcodeGen. Both project and script include the browser.
Do not replace/modify signing entitlements or initialize extra access pathways to make browsing
work. Device test must check picker cancel/denied/offline provider, back stack, Arabic LTR,
large folders, long filenames, binary plist, oversized/malformed images, symlink rejection,
and memory pressure. Access to other app containers is not promised or verified.

Private publication preparation
- Separate repository Alaaaya/Gester-Browser; no other repositories changed.
- Workflow uses Xcode's iphoneos SDK on macos-15, no signing credentials, no provisioning.
- Deployment minimum reconciled to iOS 15 across script, project and Info.plist.
- Bundle identity and upstream entitlement file unchanged. Signer must supply its own valid profile.
- Unsigned artifact is not directly installable. No certificate or App Group access promised.
- Workflow runs policy tests and validates ZIP CRC, arm64 executable, browser class, metadata,
  bundled MIT notice and absence of provisioning/signature directories before upload.
- Remote compilation and device testing remain pending until actual Actions evidence is recorded.
