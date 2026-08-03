# Changelog

All notable DiskMount changes are recorded here.

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
