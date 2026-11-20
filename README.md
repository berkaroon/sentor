# Sentor

> This project is based on https://github.com/ProxySeer/FastCommander-Releases.

**Sentor** is a clean, fast, data-integrity-focused macOS file transfer, mirror sync, and directory comparison utility built with SwiftUI and low-level POSIX/Darwin filesystem APIs for macOS 13 (Ventura) and later.

## Features

- **Copy, Move, Mirror (Sync), Delete, and Compare:** File/folder copying, moving, mirror synchronization, secure deletion (`Fast Unlink`, `Zero-Fill`, `DoD 3-Pass`), and side-by-side folder/disk comparison.
- **High-Performance POSIX Engine:** Multi-threaded parallel worker pool, APFS Copy-on-Write (`clonefile`) support on the same volume, Direct I/O (`F_NOCACHE`) for large files, and page-aligned transfer buffers.
- **100% Byte-for-Byte Verification:** Verifies every byte of transferred files from start to finish (not just file size or header/tail blocks) with automatic repair on mismatch.
- **Overwrite Policies:** `Overwrite`, `Ask me` (Windows-style per-file/batch conflict comparison dialog with a *Keep newer* option), and `Never`.
- **Fast Directory Comparison (`getattrlistbulk`):** Parallel directory indexing powered by macOS `getattrlistbulk`, with clickable `same`, `time diff`, and `diff` filter badges.
- **Queue, History, Favorites & Mini Notch HUD:** Sequential transfer queue, operation history, favorite folders, floating Mini HUD, Light/Dark themes, and English/Turkish UI.
- **Data Integrity & Security Protections:**
  - Blocks transfers/syncs when the destination is a parent or ancestor directory of the source.
  - Propagates permission/read errors on unreadable source subdirectories instead of treating them as empty and deleting destination backups.
  - Prevents symlink traversal or overwriting files outside the destination (`lstat`, `O_NOFOLLOW`, `CLONE_NOFOLLOW`).
  - Guards against zero-byte truncation when two paths (hardlink, symlink, or case-insensitive APFS alias) point to the same physical inode.
  - Protects symlink targets during secure delete (`Shred`) by unlinking only the symlink itself.
  - Enforces pre-cancellation checks before executing moves or renames.

## Requirements

- macOS 13.0+ (Ventura or later)
- Swift 5.9+ / Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

Run directly from source:

```bash
swift run
```

Build the release binary:

```bash
swift build -c release
```

Create an ad-hoc signed `.app` bundle and `.dmg` installer (`dist/Sentor.app` and `dist/Sentor.dmg`):

```bash
./scripts/build_dmg.sh
```

> [!NOTE]
> If macOS Gatekeeper warns about an unidentified developer when opening a downloaded ad-hoc signed `.app` or `.dmg`, move `Sentor.app` to `/Applications` and run:
> ```bash
> xattr -cr /Applications/Sentor.app
> ```

## License

This project is licensed under the [MIT License](LICENSE).
