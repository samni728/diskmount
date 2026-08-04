# Changelog

## 0.2.10 - 2026-08-04

DiskMount 0.2.10 is the first retained formal release.

- Fixes NTFS read/write mounting for Chinese and other non-ASCII volume names by creating a safe ASCII-only NFS mount directory while preserving the original name inside DiskMount.
- Detects external file systems written directly to a whole USB disk without a partition table, including ISO/CD9660 installer media.
- Keeps ISO/CD9660 media safely read-only while supporting discovery, Finder access, and safe eject.
- Clears stale success or error messages when one physical disk is replaced by another.
- Rejects unsafe custom mount targets and cleans up only empty DiskMount-managed mount directories.
- Includes regression coverage for whole-disk discovery, partition deduplication, mount-path safety, and physical-device replacement.

DiskMount does not format, erase, repartition, or convert disks.
