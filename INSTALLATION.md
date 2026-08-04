# DiskMount installation and permissions

[简体中文](INSTALLATION.zh-CN.md)

## Before you install

Download DiskMount only from the official [GitHub Releases page](https://github.com/samni728/diskmount/releases). Version 0.2.7 is self-contained and does not require Homebrew, Xcode, or a separate anylinuxfs installation.

The current package is signed with the developer's Apple Development certificate, but it is not signed with a Developer ID Application certificate and is not Apple-notarized. A Mac that downloads the DMG from the internet may therefore block the first launch. This Gatekeeper approval is separate from the disk permissions requested after DiskMount starts.

## Normal installation

1. Download `DiskMount-0.2.7-macOS26.dmg` and its `.sha256` file.
2. Optionally verify the download in Terminal:

   ```bash
   cd ~/Downloads
   shasum -a 256 -c DiskMount-0.2.7-macOS26.dmg.sha256
   ```

3. Open the DMG and drag `DiskMount.app` to `Applications`.
4. Open DiskMount from `Applications`. Its controls remain in the macOS menu bar.

## If macOS blocks the app

Do not disable Gatekeeper globally. Use the per-app exception provided by macOS:

1. Try to open DiskMount once and close the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and find the message that DiskMount was blocked.
4. Click **Open Anyway**. macOS normally shows this button for about one hour after the blocked launch.
5. Authenticate with the Mac login password, review the warning, and choose **Open**.

macOS then remembers DiskMount as an exception on that Mac. On organization-managed Macs, an administrator or MDM policy may still prevent this override. See Apple's [Open apps safely on your Mac](https://support.apple.com/en-ie/102445) guidance.

Avoid instructions that permanently disable Gatekeeper or indiscriminately remove quarantine attributes. Download a new copy from the official release if the checksum fails or macOS says the app is damaged.

## Permissions after launch

The following approvals serve different purposes:

1. **Administrator authorization:** NTFS read/write mounting, stopping its disk service for safe eject, and failure recovery need elevated access. DiskMount reuses a still-valid authorization session and asks again only when macOS authorization has expired. The password is passed transiently to macOS `sudo`; DiskMount does not store, log, or upload it.
2. **Full Disk Access:** enable **System Settings → Privacy & Security → Full Disk Access → DiskMount**.
3. **Removable Volumes:** when macOS shows this switch, enable **System Settings → Privacy & Security → Files & Folders → DiskMount → Removable Volumes**.
4. Fully quit and reopen DiskMount after changing either privacy permission.

DiskMount does not format, erase, repartition, or convert disks. NTFS read/write changes only the active mount method.

DiskMount contacts GitHub's public latest-Release API when it starts and when the user manually refreshes. This check sends no disk contents or administrator password, and it never downloads or installs an update automatically.

## Commercial distribution status

Version 0.2.7 is a development-signed community release. Warning-free public distribution requires a Developer ID Application certificate, hardened-runtime signing of the app and all bundled helpers, Apple notarization, and a stapled notarization ticket.
