<p align="center">
  <img src="Assets/sentor-icon-1024.png" width="140" alt="Sentor Logo" />
</p>

<h1 align="center">Sentor</h1>

<p align="center">
  <strong>A fast, data-integrity-focused macOS file transfer, mirror sync, and directory comparison utility.</strong><br/>
  Built with SwiftUI and low-level POSIX/Darwin filesystem APIs.<br/>
  This project is based on <a href="https://github.com/ProxySeer/FastCommander-Releases">https://github.com/ProxySeer/FastCommander-Releases</a>.
</p>

<p align="center">
  <a href="https://github.com/berkaroon/sentor/raw/main/dist/Sentor.dmg">
    <img src="https://img.shields.io/badge/Download-Sentor.dmg-1B4332?style=for-the-badge&logo=apple&logoColor=white" alt="Download Sentor.dmg" />
  </a>
  <img src="https://img.shields.io/badge/macOS-13.0%2B-0A84FF?style=for-the-badge" alt="macOS 13.0+" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-34C759?style=for-the-badge" alt="MIT License" />
  </a>
</p>

---

## Download & Install

- **Direct Download:** [**Sentor.dmg**](https://github.com/berkaroon/sentor/raw/main/dist/Sentor.dmg) (`3.4 MB`)
- **SHA-256:** `63173019c2b191060ef48ad7f53e2d43ed19ab4e6d9b0f90fa11a0fadbf37c41`

### Installation Steps
1. Open **`Sentor.dmg`** and drag **Sentor.app** into your **Applications** folder.
2. **First Launch (Gatekeeper):** Because Sentor is distributed independently with an ad-hoc signature rather than a paid Apple Developer ID certificate, macOS may show an *"unverified developer"* warning on first launch. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** (or run `xattr -cr /Applications/Sentor.app` in Terminal).

---

## Features

- **Copy, Move, Mirror (Sync), Delete, and Compare:** File/folder copying, moving, mirror synchronization, secure deletion (`Fast Unlink`, `Zero-Fill`, `DoD 3-Pass`), and side-by-side folder/disk comparison.
- **High-Performance POSIX Engine:** Multi-threaded parallel worker pool, APFS Copy-on-Write (`clonefile`) support on the same volume, Direct I/O (`F_NOCACHE`) for large files, and page-aligned transfer buffers.
- **100% Byte-for-Byte Verification:** Verifies every byte of transferred files from start to finish (not just file size or header/tail blocks) with automatic repair on mismatch.
- **Overwrite Policies:** `Overwrite`, `Ask me` (Windows-style per-file/batch conflict comparison dialog with a *Keep newer* option), and `Never`.
- **Fast Directory Comparison (`getattrlistbulk`):** Parallel directory indexing powered by macOS `getattrlistbulk`, with clickable `same`, `time diff`, and `diff` filter badges.
- **Queue, History, Favorites & Mini Notch HUD:** Sequential transfer queue, operation history, favorite folders, floating Mini HUD on macbook notch, Light/Dark themes, and 12 languages (en,tr,it,es,fr,de,pt,ja,zh,ko,ru)
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

## License

This project is licensed under the [MIT License](LICENSE).
