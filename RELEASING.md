# DiskMount release checklist

## Standard automated release

1. Update `VERSION` to the new semantic version.
2. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `DiskMount/project.yml`, then run `xcodegen generate`.
3. Add user-facing changes to `CHANGELOG.md`.
4. Run tests and build the local DMG.
5. Commit and push `main`.
6. Create and push an annotated tag matching `VERSION` exactly:

```bash
git tag -a v0.2.1 -m "DiskMount 0.2.1"
git push origin main
git push origin v0.2.1
```

`.github/workflows/release.yml` uses an Apple Silicon `macos-26` runner to build the self-contained DMG, verify it, create a SHA-256 file, and publish both files to a GitHub Release with generated release notes.

The workflow exits without overwriting assets when a release for that tag already exists. This allows a locally signed and manually notarized release to take priority.

## Signing status

The automated fallback build is ad-hoc signed. It is self-contained but is not Apple-notarized. A warning-free public release requires:

- Developer ID Application certificate imported into the CI keychain;
- hardened runtime signing for the app and bundled helpers;
- `notarytool submit --wait`;
- `stapler staple` before creating the final DMG;
- signing credentials stored only as encrypted GitHub Actions secrets.

Do not commit certificates, Apple IDs, app-specific passwords, API keys, or keychain files.

Private repositories consume the account's included GitHub Actions minutes and may incur usage charges after that allowance is exhausted.

## Manual verified release

```bash
cd DiskMount
./scripts/build_dmg.sh
hdiutil verify "build/DiskMount-$(tr -d '[:space:]' < ../VERSION)-macOS26.dmg"
```

Launch the app from the read-only DMG and verify:

- menu bar item and popover appear;
- English/Chinese switching works;
- Safe Mode hides system and EFI volumes;
- Expert Mode requires two confirmations before advanced-volume actions appear;
- the NTFS command includes the invoking user's `SUDO_UID` and `SUDO_GID`;
- no protected-volume mount or NTFS write test is run without an expendable test disk and a backup.
