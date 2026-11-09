# Safe Files extension 2.6

Version 2.6 exposes a single Files screen (no Gestalt, PosterBoard or Settings UI). Legacy toolbox source is retained but unreachable; startup runs no BQCore init or self-tests. This extension has no dependency on BQCore,
exploit state, MCM, or sandbox extensions. It does not make other app containers
available. Existing Files root crash fix is retained.

Reachable scope is exactly: the app's own sandbox plus folders explicitly selected in Files. No broader cross-container access, arbitrary path entry or bypass exists.

Browse and preview own sandbox or locations explicitly selected in Files.
Writes are restricted further to own Documents/tmp or user-selected provider
folders. Own root, Library and SystemData remain read-only, even when selected
through a picker. Every path component is descriptor-relative and no-follow.

Long-press a regular file to copy or edit text/plist as a NEW sibling.
The plus button creates one empty folder. Copy source max 512 KB; editor
input, XML and serialized result max 256 KB. UTF-8 only, or validated plist
preserving its original binary/XML format. Editing does not overwrite the
original. Copies stay in the same folder; no directory copy/rename or move UI.
Rename is visible but disabled: exclusive destination protection cannot exclude a concurrent source replacement. No user-facing deletion, overwrite, restore, recursive backup or automatic
access to other apps is implemented.

Every operation prepares a binary plist backup envelope. For file operations
it contains the complete original file bytes plus a parent directory metadata
manifest; for empty-folder creation it contains the parent manifest only.
The envelope is staged privately in Caches, then exported via Files. Nothing
in the source folder is changed yet. Export completion is not considered proof.
The user must re-open the saved envelope through Files, from OUTSIDE both the
app sandbox and selected source root. The reopened regular file must match
every staged byte within a 2 MB bound. A cancelled export/open, mismatched file,
or inability to read the external backup cancels without source changes.
The staged private backup is removed after completion/cancellation, not the
external backup. Backups are not encrypted by this app; choose a trusted location.

A final confirmation identifies the operation, old/new names and sizes.
At execution, an NSFileCoordinator write intent is obtained, the directory
URL/descriptor identity is compared, a fresh <=2,000-entry metadata manifest
must match, and the original file bytes must still match. Exclusive creation
reject existing targets including symbolic links.
Successful new file contents are read back; new
folders are checked as directories. Failed verification asks the user to inspect
before retrying. No original file content is overwritten.

Limits: document-provider coordination is cooperative, not a global lock against
a hostile/non-cooperating filesystem writer. There is no crash-recovery journal;
a crash/I/O error during new-copy creation may leave an incomplete NEW file, but
not overwrite the original. There is no restore UI; retain the external envelope
for manual recovery. An export/readback proves bytes at that instant, not that a
cloud provider has finished remote synchronization. If a provider can't satisfy
the verification and descriptor requirements, the change is refused.

Arabic and English use LTR structure. The explanatory header and row descriptions
size to their complete text, including large Dynamic Type and rotation.

Tests include native no-overwrite/name/link policy cases and an isolated
simulator harness covering backup/confirmation gates, cancellation, invalid plist editing, and English/Arabic LTR header layout. The harness suppresses pickers and does not prove actual export/provider access. Export picker navigation, cloud sync, LCSign signing, physical
device installation/runtime, and hostile concurrent-provider behavior need real
device verification; do not describe those as tested.
