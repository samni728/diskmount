# Changelog

## 0.2.3 - 2026-08-03

- Clarified that administrator authorization is used only for DiskMount NTFS mounting and failure recovery.
- Clarified that the administrator password is passed transiently to macOS `sudo` and is never stored, logged, or uploaded.
- Added explicit Full Disk Access and Removable Volumes permission guidance to the app, Info.plist, and bilingual documentation.
- Reworked the English and Simplified Chinese README files around the current permission model, installation flow, and safety boundaries.
- Replaced the outdated README images with verified 0.2.3 English and Chinese screenshots for both Safe Mode and Expert Mode.
- Added the 0.2.3 administrator authorization prompt to both README versions so users can recognize the required workflow before installation.
- Published the release as a standard GitHub Release rather than a pre-release.

## 0.2.2 - 2026-08-03

- Fixed the NTFS launch chain so the bundled engine is started through a real `sudo` process after macOS administrator authorization.
- Removed the unreliable app-level raw-device preflight; the bundled engine now performs the authoritative access check.
- Automatically restores the normal macOS read-only mount if the NTFS engine fails.
- Keeps the macOS `sudo` authorization timestamp alive while DiskMount remains open, so later automatic mounts do not ask for the password again during the same app session.
- Remembers NTFS disks by a stable hardware/partition fingerprint and automatically retries read/write mounting when a remembered disk is inserted.
- Added a per-disk control to enable or disable automatic NTFS read/write mounting.
- Corrected privacy guidance to distinguish Full Disk Access from Removable Volumes access.
- Shows a clear `NTFS Writable` / `NTFS 可写` state after a successful read/write mount instead of offering another mount action.

All notable DiskMount changes are recorded here.

## 0.2.1 - 2026-08-03

### Fixed

- declare removable-volume access in the app bundle so macOS can authorize raw external-disk reads used by anylinuxfs;
- recognize macOS/TCC raw-disk denials and replace the upstream `Cannot probe` error with actionable bilingual guidance;
- add a one-click shortcut to the Files & Folders privacy settings when removable-volume access is blocked.

### Security

- administrator approval and removable-volume privacy consent remain separate, explicit user decisions;
- the new permission flow does not add any format, erase, conversion, or repartition operation.

## 0.2.0 - 2026-08-03

### Added

- English and Simplified Chinese interface with a persistent language switch;
- English-first project homepage and a separate Chinese README;
- fixed header/footer layout with an independently scrollable device list;
- per-volume Expert Mode authorization for EFI and other advanced volumes;
- automatic GitHub Release workflow for version tags;
- English, Chinese, and Expert Mode screenshots.

### Fixed

- Forward the real invoking user's UID/GID through the macOS administrator authorization flow so anylinuxfs no longer rejects the process as a bare root invocation;
- clear stale operation messages after changing language or leaving Expert Mode.

### Safety

- Advanced access is session-only and requires a second confirmation per volume;
- protected whole-disk eject remains blocked;
- DiskMount does not bypass SIP, force sealed system volumes writable, format, erase, convert, or repartition disks.

## 0.1.3 - 2026-08-03

- Renamed the advanced-view control to Expert Mode;
- fixed the header and footer while keeping only the device list scrollable;
- reduced excess panel height and whitespace.

## 0.1.2 - 2026-08-03

- Fixed the AppKit lifecycle so the menu bar item and popover appear reliably;
- added the app icon, logo, device details, safe system-volume filtering, repository link, and Star button;
- bundled the ARM64 anylinuxfs runtime for independent installation.
