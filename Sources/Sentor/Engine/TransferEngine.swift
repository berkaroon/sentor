import Foundation
import Darwin
import Security

struct TransferTelemetry {
    var progress: Double = 0
    var speedMBps: Double = 0
    var peakMBps: Double = 0
    var filesPerSec: Int = 0
    var filesDone: Int = 0
    var filesTotal: Int = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var etaText: String = "--:--"
    var currentFile: String = ""
    var diffs: [FileDiffItem] = []

    var bytesDoneText: String { TransferEngine.formatBytes(bytesDone) }
    var bytesTotalText: String { TransferEngine.formatBytes(bytesTotal) }
}

final class TransferControl: @unchecked Sendable {
    private let lock = NSLock()
    private let conflictLock = NSLock()
    private let skippedLock = NSLock()
    private var _isCancelled = false
    private var _isPaused = false
    private var applyAllAction: FileConflictAction?
    private var _skippedPaths: Set<String> = []

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isPaused
    }

    func cancel() {
        lock.lock(); _isCancelled = true; _isPaused = false; lock.unlock()
    }

    func setPaused(_ paused: Bool) {
        lock.lock(); _isPaused = paused; lock.unlock()
    }

    func waitIfPaused() -> Bool {
        while isPaused {
            if isCancelled { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !isCancelled
    }

    func resolveConflict(_ info: FileConflictInfo, handler: ((FileConflictInfo) -> FileConflictDecision)?) -> FileConflictAction {
        conflictLock.lock()
        defer { conflictLock.unlock() }
        if isCancelled { return .cancel }
        if let preset = applyAllAction { return preset }
        guard let handler else { return .overwrite }
        let decision = handler(info)
        if decision.applyToAll && decision.action != .cancel {
            applyAllAction = decision.action
        }
        return decision.action
    }

    func markSkipped(_ normPath: String) {
        skippedLock.lock()
        _skippedPaths.insert(normPath)
        skippedLock.unlock()
    }

    func isSkipped(_ normPath: String) -> Bool {
        skippedLock.lock()
        let res = _skippedPaths.contains(normPath)
        skippedLock.unlock()
        return res
    }
}

enum TransferEngineError: LocalizedError {
    case sourceNotFound(String)
    case cancelled
    case cancellationIncomplete
    case verificationFailed(String)
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let p): return "Source not found: \(p)"
        case .cancelled: return "Operation cancelled"
        case .cancellationIncomplete: return "Cancellation stopped the transfer, but the destination may contain changes. Check it before continuing the queue."
        case .verificationFailed(let p): return "Verification failed: \(p)"
        case .ioError(let msg): return msg
        }
    }
}

final class TransferEngine {
    static let chunkSizes = [1, 2, 4, 8, 16].map { $0 * 1024 * 1024 }
    static let directIOThreshold: Int64 = 64 * 1024 * 1024
    static let preallocateThreshold: Int64 = 1_048_576
    static let largeFileThreshold: Int64 = 16 * 1024 * 1024

    // MARK: - Dynamic Volume Inspection
    static func inspectVolumes(source: String, destination: String, mode: TransferMode) -> (banner: String, samePhysicalDisk: Bool) {
        let srcURL = existingAncestorURL(for: source)
        let dstURL = existingAncestorURL(for: destination)

        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeIdentifierKey]
        let srcVals = try? srcURL?.resourceValues(forKeys: keys)
        let srcName = srcVals?.volumeName ?? "Local Disk"
        let srcFmt = srcVals?.volumeLocalizedFormatDescription ?? "APFS"

        if mode == .delete {
            return ("\(srcName) (\(srcFmt)) · Target Volume", false)
        }
        if mode == .diff {
            return ("\(srcName) (\(srcFmt)) · Read-Only Diff", false)
        }

        let dstVals = try? dstURL?.resourceValues(forKeys: keys)
        let dstName = dstVals?.volumeName ?? "Destination"
        let dstFmt = dstVals?.volumeLocalizedFormatDescription ?? "APFS"

        let sameDisk: Bool
        if let id1 = srcVals?.volumeIdentifier as? NSObject,
           let id2 = dstVals?.volumeIdentifier as? NSObject {
            sameDisk = id1.isEqual(id2)
        } else {
            sameDisk = (srcName == dstName)
        }

        let suffix = sameDisk ? "Same Physical Drive · Turn-Taking" : "Parallel I/O"
        return ("\(srcName) (\(srcFmt)) → \(dstName) (\(dstFmt)) · \(suffix)", sameDisk)
    }

    private static func existingAncestorURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var url = URL(fileURLWithPath: trimmed)
        let fm = FileManager.default
        while !fm.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return url
    }

    // MARK: - Destination Profile
    private struct DestinationProfile {
        let canAPFSClone: Bool
        let isFATOrExFAT: Bool
        let timestampTolerance: TimeInterval
        let workerCount: Int
    }

    private static func buildProfile(src: String, dst: String, cloneRequested: Bool, settings: SentorSettings) -> DestinationProfile {
        let srcURL = existingAncestorURL(for: src)
        let dstURL = existingAncestorURL(for: dst)
        let keys: Set<URLResourceKey> = [
            .volumeIdentifierKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsLocalKey,
            .volumeIsRemovableKey
        ]
        let srcVals = try? srcURL?.resourceValues(forKeys: keys)
        let dstVals = try? dstURL?.resourceValues(forKeys: keys)

        let sameVol: Bool
        if let id1 = srcVals?.volumeIdentifier as? NSObject,
           let id2 = dstVals?.volumeIdentifier as? NSObject {
            sameVol = id1.isEqual(id2)
        } else {
            sameVol = false
        }

        let srcFmt = (srcVals?.volumeLocalizedFormatDescription ?? "").uppercased()
        let fmt = (dstVals?.volumeLocalizedFormatDescription ?? "").uppercased()
        let canClone = cloneRequested
            && sameVol
            && srcFmt.contains("APFS")
            && fmt.contains("APFS")
        let isFAT = fmt.contains("FAT") || fmt.contains("MS-DOS") || fmt.contains("EXFAT")
        let isNetwork = (dstVals?.volumeIsLocal == false)
        let isRemovable = (dstVals?.volumeIsRemovable == true)

        let workers: Int
        if settings.autoTuneWorkers {
            if canClone {
                workers = min(max(settings.maxParallelFiles, 16), 32)
            } else if isFAT || isRemovable || isNetwork {
                workers = 4
            } else {
                workers = min(max(settings.maxParallelFiles, 8), 16)
            }
        } else {
            workers = max(1, min(settings.maxParallelFiles, 64))
        }

        return DestinationProfile(
            canAPFSClone: canClone,
            isFATOrExFAT: isFAT,
            timestampTolerance: isFAT ? 2.0 : 1.0,
            workerCount: workers
        )
    }

    private static func normKey(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
    }

    // MARK: - Canonical & Physical Path Helpers
    private static func canonicalVFSPath(_ rawPath: String) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        var currentURL = URL(fileURLWithPath: expanded).standardizedFileURL
        var suffix: [String] = []

        while !pathExistsPOSIX(currentURL.path) && currentURL.path != "/" {
            suffix.append(currentURL.lastPathComponent)
            currentURL.deleteLastPathComponent()
        }

        let resolvedURL = currentURL.resolvingSymlinksInPath()
        var baseCanonical = resolvedURL.path

        let fd = Darwin.open(resolvedURL.path, O_RDONLY)
        if fd >= 0 {
            defer { Darwin.close(fd) }
            var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if Darwin.fcntl(fd, F_GETPATH, &pathBuf) != -1 {
                baseCanonical = String(cString: pathBuf)
            }
        } else {
            let symFd = Darwin.open(resolvedURL.path, O_RDONLY | O_SYMLINK)
            if symFd >= 0 {
                defer { Darwin.close(symFd) }
                var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                if Darwin.fcntl(symFd, F_GETPATH, &pathBuf) != -1 {
                    baseCanonical = String(cString: pathBuf)
                }
            }
        }

        var finalURL = URL(fileURLWithPath: baseCanonical)
        for comp in suffix.reversed() {
            finalURL.appendPathComponent(comp)
        }
        return finalURL.standardizedFileURL.path
    }

    private static func isSameOrDescendantPath(_ candidate: String, of base: String) -> Bool {
        if candidate == base { return true }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return candidate.hasPrefix(prefix)
    }

    private static func samePhysicalObject(_ pathA: String, _ pathB: String) -> Bool {
        var stA = stat()
        var stB = stat()
        let hasStatA = (Darwin.fstatat(AT_FDCWD, pathA, &stA, 0) == 0)
        let hasStatB = (Darwin.fstatat(AT_FDCWD, pathB, &stB, 0) == 0)
        if hasStatA && hasStatB && stA.st_dev == stB.st_dev && stA.st_ino == stB.st_ino {
            return true
        }

        var lstA = stat()
        var lstB = stat()
        let hasLstatA = (Darwin.lstat(pathA, &lstA) == 0)
        let hasLstatB = (Darwin.lstat(pathB, &lstB) == 0)
        if hasLstatA && hasLstatB && lstA.st_dev == lstB.st_dev && lstA.st_ino == lstB.st_ino {
            return true
        }
        if hasStatA && hasLstatB && stA.st_dev == lstB.st_dev && stA.st_ino == lstB.st_ino {
            return true
        }
        if hasLstatA && hasStatB && lstA.st_dev == stB.st_dev && lstA.st_ino == stB.st_ino {
            return true
        }
        return false
    }

    private static func isSymbolicLinkPOSIX(_ path: String) -> Bool {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    // MARK: - Destination Path Resolution (x -> y/x)
    static func resolveDestinationPath(src: String, dst: String) -> String {
        let fm = FileManager.default
        let srcStd = URL(fileURLWithPath: (src as NSString).expandingTildeInPath).standardizedFileURL.path
        let dstStd = URL(fileURLWithPath: (dst as NSString).expandingTildeInPath).standardizedFileURL.path
        let srcName = (srcStd as NSString).lastPathComponent
        guard !srcName.isEmpty else { return dstStd }

        var srcIsDir: ObjCBool = false
        guard fm.fileExists(atPath: srcStd, isDirectory: &srcIsDir) else { return dstStd }

        if srcIsDir.boolValue {
            if (dstStd as NSString).lastPathComponent != srcName {
                return (dstStd as NSString).appendingPathComponent(srcName)
            }
            return dstStd
        } else {
            var dstIsDir: ObjCBool = false
            let dstExists = fm.fileExists(atPath: dstStd, isDirectory: &dstIsDir)
            if dstExists && dstIsDir.boolValue {
                return (dstStd as NSString).appendingPathComponent(srcName)
            }
            return dstStd
        }
    }

    // MARK: - Execute Transfer
    static func execute(
        mode: TransferMode,
        sourcePath: String,
        destinationPath: String,
        overwriteRule: OverwriteRule,
        shredPass: ShredPassOption,
        enableBlockClone: Bool,
        preserveTimestamps: Bool,
        settings: SentorSettings,
        control: TransferControl,
        onConflict: ((FileConflictInfo) -> FileConflictDecision)? = nil,
        onProgress: @escaping (TransferTelemetry) -> Void
    ) throws -> TransferTelemetry {
        if !control.waitIfPaused() {
            throw TransferEngineError.cancelled
        }

        let fm = FileManager.default
        let src = (sourcePath as NSString).expandingTildeInPath
        let dst = (destinationPath as NSString).expandingTildeInPath

        let srcExists = (mode == .delete) ? pathExistsPOSIX(src) : (fm.fileExists(atPath: src) || pathExistsPOSIX(src))
        guard srcExists else {
            throw TransferEngineError.sourceNotFound(src)
        }

        let effectiveDst = (mode == .delete) ? dst : resolveDestinationPath(src: src, dst: dst)

        if mode == .copy || mode == .move || mode == .sync || mode == .diff {
            if isSymbolicLinkPOSIX(dst) || isSymbolicLinkPOSIX(effectiveDst) {
                throw TransferEngineError.ioError("Security error: destination path cannot be a symbolic link.")
            }

            if samePhysicalObject(src, dst) || samePhysicalObject(src, effectiveDst) {
                throw TransferEngineError.ioError("Source and destination refer to the same physical file or directory.")
            }

            let sourceCanon = canonicalVFSPath(src)
            let rawTargetCanon = canonicalVFSPath(dst)
            let effectiveTargetCanon = canonicalVFSPath(effectiveDst)

            let lexicalSource = URL(fileURLWithPath: src).standardizedFileURL.path
            let lexicalRawTarget = URL(fileURLWithPath: dst).standardizedFileURL.path
            let lexicalEffectiveTarget = URL(fileURLWithPath: effectiveDst).standardizedFileURL.path

            if isSameOrDescendantPath(effectiveTargetCanon, of: sourceCanon) ||
                isSameOrDescendantPath(rawTargetCanon, of: sourceCanon) ||
                isSameOrDescendantPath(lexicalEffectiveTarget, of: lexicalSource) ||
                isSameOrDescendantPath(lexicalRawTarget, of: lexicalSource) {
                throw TransferEngineError.ioError("The destination cannot be the source or inside it.")
            }

            var srcIsDir: ObjCBool = false
            _ = fm.fileExists(atPath: src, isDirectory: &srcIsDir)
            if srcIsDir.boolValue || mode == .sync {
                if isSameOrDescendantPath(sourceCanon, of: effectiveTargetCanon) ||
                    isSameOrDescendantPath(sourceCanon, of: rawTargetCanon) ||
                    isSameOrDescendantPath(lexicalSource, of: lexicalEffectiveTarget) ||
                    isSameOrDescendantPath(lexicalSource, of: lexicalRawTarget) {
                    throw TransferEngineError.ioError("The destination cannot be a parent or ancestor directory of the source.")
                }
            } else {
                if sourceCanon == effectiveTargetCanon || sourceCanon == rawTargetCanon ||
                    lexicalSource == lexicalEffectiveTarget || lexicalSource == lexicalRawTarget {
                    throw TransferEngineError.ioError("Source and destination refer to the same file.")
                }
            }
        }

        if mode == .move && (fm.fileExists(atPath: effectiveDst) || pathExistsPOSIX(effectiveDst)) {
            throw TransferEngineError.ioError("Move destination already exists. Choose a different destination.")
        }

        switch mode {
        case .copy:
            return try runCopy(src: src, dst: effectiveDst, overwrite: overwriteRule, clone: enableBlockClone, preserve: preserveTimestamps, settings: settings, control: control, onConflict: onConflict, onProgress: onProgress)
        case .move:
            return try runMove(src: src, dst: effectiveDst, overwrite: overwriteRule, clone: enableBlockClone, preserve: preserveTimestamps, settings: settings, control: control, onConflict: onConflict, onProgress: onProgress)
        case .sync:
            return try runMirrorSync(src: src, dst: effectiveDst, overwrite: overwriteRule, clone: enableBlockClone, preserve: preserveTimestamps, settings: settings, control: control, onConflict: onConflict, onProgress: onProgress)
        case .diff:
            return try runDiff(src: src, dst: effectiveDst, control: control, onProgress: onProgress)
        case .delete:
            return try runDelete(target: src, shredPass: shredPass, workers: settings.deleteWorkers, control: control, onProgress: onProgress)
        }
    }

    // MARK: - Fast POSIX Enumeration
    private struct FileEntry {
        let srcPath: String
        let relativePath: String
        let size: Int64
        let mtimeSec: TimeInterval
        let mtimeSpec: timespec
        let mode: mode_t
    }

    private struct ScanResult {
        let isSingleFile: Bool
        let entries: [FileEntry]
        let dirs: [String]
        let totalBytes: Int64
    }

    private static func fastEnumerateEntries(
        root: String,
        checkReadable: Bool = false,
        includeNonRegularEntries: Bool = false,
        rejectSymlinks: Bool = false,
        followRootSymlink: Bool = false
    ) throws -> ScanResult {
        var st = stat()
        guard Darwin.lstat(root, &st) == 0 else {
            let err = errno
            throw TransferEngineError.ioError("Failed to access \(root): \(String(cString: strerror(err)))")
        }

        if (st.st_mode & S_IFMT) == S_IFLNK {
            if rejectSymlinks {
                throw TransferEngineError.ioError("Security error: symbolic link not allowed at \(root)")
            }
            if followRootSymlink {
                var targetSt = stat()
                guard Darwin.fstatat(AT_FDCWD, root, &targetSt, 0) == 0 else {
                    let err = errno
                    throw TransferEngineError.ioError("Failed to resolve symbolic link \(root): \(String(cString: strerror(err)))")
                }
                st = targetSt
            }
        }

        if (st.st_mode & S_IFMT) != S_IFDIR {
            let fileType = st.st_mode & S_IFMT
            if checkReadable && fileType == S_IFREG {
                let testFd = Darwin.open(root, O_RDONLY)
                if testFd < 0 {
                    let err = errno
                    throw TransferEngineError.ioError("Permission denied reading \(root): \(String(cString: strerror(err)))")
                }
                Darwin.close(testFd)
            }
            let name = (root as NSString).lastPathComponent
            let mtime = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
            let effectiveSize: Int64 = (fileType == S_IFREG) ? Int64(st.st_size) : 0
            let entry = FileEntry(
                srcPath: root,
                relativePath: name,
                size: effectiveSize,
                mtimeSec: mtime,
                mtimeSpec: st.st_mtimespec,
                mode: st.st_mode
            )
            return ScanResult(isSingleFile: true, entries: [entry], dirs: [], totalBytes: effectiveSize)
        }

        var entries: [FileEntry] = []
        var dirs: [String] = []
        var totalBytes: Int64 = 0
        var stack: [(fullPath: String, relPrefix: String)] = [(root, "")]

        while let current = stack.popLast() {
            guard let dir = Darwin.opendir(current.fullPath) else {
                let err = errno
                throw TransferEngineError.ioError("Permission denied or failed to open directory \(current.fullPath): \(String(cString: strerror(err)))")
            }
            let dfd = Darwin.dirfd(dir)
            while true {
                errno = 0
                guard let ent = Darwin.readdir(dir) else {
                    let err = errno
                    if err != 0 {
                        Darwin.closedir(dir)
                        throw TransferEngineError.ioError("Failed to read directory \(current.fullPath): \(String(cString: strerror(err)))")
                    }
                    break
                }
                let name = withUnsafePointer(to: ent.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }

                let childFull = current.fullPath.hasSuffix("/") ? current.fullPath + name : current.fullPath + "/" + name
                let childRel = current.relPrefix.isEmpty ? name : current.relPrefix + "/" + name

                var childStat = stat()
                if Darwin.fstatat(dfd, name, &childStat, AT_SYMLINK_NOFOLLOW) != 0 {
                    let err = errno
                    Darwin.closedir(dir)
                    throw TransferEngineError.ioError("Failed to inspect \(childFull): \(String(cString: strerror(err)))")
                }

                let modeType = childStat.st_mode & S_IFMT
                if modeType == S_IFLNK && rejectSymlinks {
                    Darwin.closedir(dir)
                    throw TransferEngineError.ioError("Security error: symbolic link inside destination is not allowed (\(childFull))")
                }

                if modeType == S_IFDIR {
                    dirs.append(childRel)
                    stack.append((childFull, childRel))
                } else if modeType == S_IFREG {
                    if checkReadable {
                        let childFd = Darwin.openat(dfd, name, O_RDONLY | O_NOFOLLOW)
                        if childFd < 0 {
                            let err = errno
                            Darwin.closedir(dir)
                            throw TransferEngineError.ioError("Permission denied reading \(childFull): \(String(cString: strerror(err)))")
                        }
                        Darwin.close(childFd)
                    }
                    let sz = Int64(childStat.st_size)
                    let mtime = TimeInterval(childStat.st_mtimespec.tv_sec) + TimeInterval(childStat.st_mtimespec.tv_nsec) / 1_000_000_000.0
                    totalBytes += sz
                    entries.append(FileEntry(
                        srcPath: childFull,
                        relativePath: childRel,
                        size: sz,
                        mtimeSec: mtime,
                        mtimeSpec: childStat.st_mtimespec,
                        mode: childStat.st_mode
                    ))
                } else if includeNonRegularEntries {
                    let mtime = TimeInterval(childStat.st_mtimespec.tv_sec) + TimeInterval(childStat.st_mtimespec.tv_nsec) / 1_000_000_000.0
                    entries.append(FileEntry(
                        srcPath: childFull,
                        relativePath: childRel,
                        size: 0,
                        mtimeSec: mtime,
                        mtimeSpec: childStat.st_mtimespec,
                        mode: childStat.st_mode
                    ))
                }
            }
            Darwin.closedir(dir)
        }

        dirs.sort { $0.count < $1.count }
        return ScanResult(isSingleFile: false, entries: entries, dirs: dirs, totalBytes: totalBytes)
    }

    // MARK: - Throttled Telemetry State
    private final class ProgressAggregator: @unchecked Sendable {
        private let lock = NSLock()
        private var telemetry: TransferTelemetry
        private let startTime: Date
        private var lastEmitTime: CFAbsoluteTime = 0
        private let onProgress: (TransferTelemetry) -> Void

        init(filesTotal: Int, bytesTotal: Int64, onProgress: @escaping (TransferTelemetry) -> Void) {
            self.telemetry = TransferTelemetry(filesTotal: filesTotal, bytesTotal: bytesTotal)
            self.startTime = Date()
            self.onProgress = onProgress
        }

        func add(bytes: Int64, files: Int, currentFile: String) {
            lock.lock()
            telemetry.bytesDone += bytes
            telemetry.filesDone += files
            telemetry.currentFile = currentFile
            let now = CFAbsoluteTimeGetCurrent()
            let shouldEmit = (now - lastEmitTime) >= 0.08
            if shouldEmit {
                lastEmitTime = now
                updateRatesLocked()
                let snap = telemetry
                lock.unlock()
                onProgress(snap)
            } else {
                lock.unlock()
            }
        }

        func reportVerifyProgress(checked: Int, total: Int) {
            lock.lock()
            telemetry.currentFile = "Double-Check verifying: \(checked)/\(total) files"
            let now = CFAbsoluteTimeGetCurrent()
            let shouldEmit = (now - lastEmitTime) >= 0.08 || checked == total
            if shouldEmit {
                lastEmitTime = now
                let snap = telemetry
                lock.unlock()
                onProgress(snap)
            } else {
                lock.unlock()
            }
        }

        func finish(statusText: String) -> TransferTelemetry {
            lock.lock()
            updateRatesLocked()
            telemetry.progress = 1.0
            telemetry.etaText = "00:00"
            telemetry.currentFile = statusText
            let snap = telemetry
            lock.unlock()
            onProgress(snap)
            return snap
        }

        private func updateRatesLocked() {
            let elapsed = max(0.05, Date().timeIntervalSince(startTime))
            let mbps = (Double(telemetry.bytesDone) / (1024.0 * 1024.0)) / elapsed
            telemetry.speedMBps = mbps
            if elapsed >= 0.25 {
                telemetry.peakMBps = max(telemetry.peakMBps, mbps)
            }
            telemetry.filesPerSec = Int(Double(telemetry.filesDone) / elapsed)
            if telemetry.bytesTotal > 0 {
                telemetry.progress = min(1.0, Double(telemetry.bytesDone) / Double(telemetry.bytesTotal))
                let remainingBytes = max(0, telemetry.bytesTotal - telemetry.bytesDone)
                let bytesPerSec = Double(telemetry.bytesDone) / elapsed
                if bytesPerSec > 0 {
                    let sec = Int(Double(remainingBytes) / bytesPerSec)
                    telemetry.etaText = String(format: "%02d:%02d", sec / 60, sec % 60)
                }
            } else {
                telemetry.progress = telemetry.filesTotal > 0 ? Double(telemetry.filesDone) / Double(telemetry.filesTotal) : 1.0
            }
        }
    }

    private static func pathExistsPOSIX(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    private static func isDirectoryPOSIX(_ path: String) -> Bool {
        var st = stat()
        var res = stat(path, &st)
        if res != 0 { res = lstat(path, &st) }
        return res == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    private final class RollbackTracker: @unchecked Sendable {
        let dstRoot: String
        let dstExistedBefore: Bool
        private let lock = NSLock()
        private var writtenFiles: Set<String> = []
        private var createdDirs: Set<String> = []

        init(dstRoot: String, dstExistedBefore: Bool) {
            self.dstRoot = dstRoot
            self.dstExistedBefore = dstExistedBefore
        }

        func recordFile(_ path: String) {
            lock.lock()
            writtenFiles.insert(path)
            lock.unlock()
        }

        func recordDir(_ path: String) {
            lock.lock()
            createdDirs.insert(path)
            lock.unlock()
        }

        func snapshot() -> (files: [String], dirs: [String]) {
            lock.lock()
            let f = Array(writtenFiles)
            let d = Array(createdDirs)
            lock.unlock()
            return (f, d)
        }
    }

    // Never remove overwritten pre-existing files: their original contents cannot be restored.
    private static func rollbackCancelledDestination(tracker: RollbackTracker) throws {
        if tracker.dstExistedBefore {
            let snapshot = tracker.snapshot()
            if !snapshot.files.isEmpty || !snapshot.dirs.isEmpty {
                throw TransferEngineError.cancellationIncomplete
            }
            return
        }
        let snapshot = tracker.snapshot()
        var incomplete = false
        // Only remove paths this transfer recorded. Never recursively delete unrelated arrivals.
        for file in snapshot.files {
            if Darwin.unlink(file) != 0 && errno != ENOENT { incomplete = true }
        }
        for dir in snapshot.dirs.sorted(by: { $0.count > $1.count }) {
            if Darwin.rmdir(dir) != 0 && errno != ENOENT { incomplete = true }
        }
        if incomplete { throw TransferEngineError.cancellationIncomplete }
    }

    private static func removeTreePOSIX(path: String) {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        if (st.st_mode & S_IFMT) == S_IFDIR {
            if let dir = opendir(path) {
                while let ent = readdir(dir) {
                    let name = withUnsafePointer(to: &ent.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.d_namlen) + 1) {
                            String(cString: $0)
                        }
                    }
                    if name == "." || name == ".." { continue }
                    let child = path.hasSuffix("/") ? path + name : path + "/" + name
                    removeTreePOSIX(path: child)
                }
                closedir(dir)
            }
            Darwin.chflags(path, 0)
            Darwin.chmod(path, 0o755)
            Darwin.rmdir(path)
        } else {
            Darwin.chflags(path, 0)
            Darwin.chmod(path, 0o644)
            Darwin.unlink(path)
        }
    }

    // MARK: - Directory Pre-Creation & Symlink-Safe Path Validation
    private static func validateNoSymlinksInDestinationAncestry(targetPath: String, dstRoot: String) throws {
        let stdRoot = URL(fileURLWithPath: dstRoot).standardizedFileURL.path
        let stdTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.path

        var rootStat = stat()
        if Darwin.lstat(stdRoot, &rootStat) == 0 {
            if (rootStat.st_mode & S_IFMT) == S_IFLNK {
                throw TransferEngineError.ioError("Security error: destination root is a symbolic link (\(stdRoot))")
            }
        }

        let parentPath = (stdTarget as NSString).deletingLastPathComponent
        if parentPath == stdRoot || parentPath.hasPrefix(stdRoot.hasSuffix("/") ? stdRoot : stdRoot + "/") {
            let relPart = String(parentPath.dropFirst(stdRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !relPart.isEmpty {
                var cur = stdRoot
                for comp in relPart.split(separator: "/") {
                    cur = cur.hasSuffix("/") ? cur + comp : cur + "/" + comp
                    var st = stat()
                    if Darwin.lstat(cur, &st) == 0 {
                        if (st.st_mode & S_IFMT) == S_IFLNK {
                            throw TransferEngineError.ioError("Security error: symbolic link inside destination is not allowed (\(cur))")
                        }
                        if (st.st_mode & S_IFMT) != S_IFDIR {
                            throw TransferEngineError.ioError("Destination component is not a directory (\(cur))")
                        }
                    }
                }
            }
        }
    }

    private static func mkdirRecursivePOSIX(_ path: String, dstRoot: String? = nil, tracker: RollbackTracker? = nil) throws {
        let stdRoot = dstRoot.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        var current = path.hasPrefix("/") ? "" : "."
        for comp in components where !comp.isEmpty {
            current += "/" + comp
            let isWithinDstRoot: Bool
            if let root = stdRoot {
                let stdCur = URL(fileURLWithPath: current).standardizedFileURL.path
                isWithinDstRoot = (stdCur == root) || stdCur.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            } else {
                isWithinDstRoot = (current == path)
            }

            var st = stat()
            if Darwin.lstat(current, &st) == 0 {
                if isWithinDstRoot {
                    if (st.st_mode & S_IFMT) == S_IFLNK {
                        throw TransferEngineError.ioError("Security error: symbolic link inside destination is not allowed (\(current))")
                    }
                    if (st.st_mode & S_IFMT) != S_IFDIR {
                        throw TransferEngineError.ioError("Destination path component is not a directory (\(current))")
                    }
                }
            } else {
                if Darwin.mkdir(current, 0o755) == 0 {
                    tracker?.recordDir(current)
                } else if errno == EEXIST {
                    if Darwin.lstat(current, &st) == 0 {
                        if (st.st_mode & S_IFMT) == S_IFLNK {
                            throw TransferEngineError.ioError("Security error: symbolic link inside destination is not allowed (\(current))")
                        }
                        if isWithinDstRoot && (st.st_mode & S_IFMT) != S_IFDIR {
                            throw TransferEngineError.ioError("Destination path component is not a directory (\(current))")
                        }
                    }
                } else {
                    throw TransferEngineError.ioError("mkdir failed for \(current): \(String(cString: strerror(errno)))")
                }
            }
        }
    }

    // MARK: - Copy (Parallel Worker Pool + Reusable Aligned Buffers + 2-Layer Verification)
    private static func runCopy(
        src: String,
        dst: String,
        overwrite: OverwriteRule,
        clone: Bool,
        preserve: Bool,
        settings: SentorSettings,
        control: TransferControl,
        onConflict: ((FileConflictInfo) -> FileConflictDecision)? = nil,
        onProgress: @escaping (TransferTelemetry) -> Void
    ) throws -> TransferTelemetry {
        if !control.waitIfPaused() { throw TransferEngineError.cancelled }
        let scan = try fastEnumerateEntries(root: src, checkReadable: true, followRootSymlink: true)
        if !control.waitIfPaused() { throw TransferEngineError.cancelled }
        onProgress(TransferTelemetry(filesTotal: scan.entries.count, bytesTotal: scan.totalBytes))
        let profile = buildProfile(src: src, dst: dst, cloneRequested: clone, settings: settings)
        let chunkSize = chunkSizes[min(max(settings.chunkSizeIndex, 0), chunkSizes.count - 1)]

        let dstExistedBefore = pathExistsPOSIX(dst)
        if dstExistedBefore && isSymbolicLinkPOSIX(dst) {
            throw TransferEngineError.ioError("Security error: destination path cannot be a symbolic link (\(dst))")
        }

        let tracker = RollbackTracker(dstRoot: dst, dstExistedBefore: dstExistedBefore)
        if !scan.isSingleFile {
            try mkdirRecursivePOSIX(dst, dstRoot: dst, tracker: tracker)
        } else {
            let parent = (dst as NSString).deletingLastPathComponent
            try mkdirRecursivePOSIX(parent, dstRoot: parent, tracker: tracker)
        }

        // Destination Pre-Scan: always verify no symlinks exist inside dst when dst existed before,
        // and build O(1) lookup map when overwrite != .always.
        var dstLookup: [String: (size: Int64, mtimeSec: TimeInterval)]? = nil
        var singleFilePreexisting: (exists: Bool, mtimeSec: TimeInterval)? = nil
        if dstExistedBefore {
            if scan.isSingleFile, let only = scan.entries.first {
                let targetPath = isDirectoryPOSIX(dst)
                    ? (dst.hasSuffix("/") ? dst + only.relativePath : dst + "/" + only.relativePath)
                    : dst
                if samePhysicalObject(only.srcPath, targetPath) {
                    throw TransferEngineError.ioError("Source and destination refer to the same physical file (\(targetPath))")
                }
                var fStat = stat()
                if Darwin.lstat(targetPath, &fStat) == 0 {
                    if (fStat.st_mode & S_IFMT) == S_IFLNK {
                        throw TransferEngineError.ioError("Security error: destination file is a symbolic link (\(targetPath))")
                    }
                    let mtime = TimeInterval(fStat.st_mtimespec.tv_sec) + TimeInterval(fStat.st_mtimespec.tv_nsec) / 1_000_000_000.0
                    singleFilePreexisting = (true, mtime)
                }
            } else {
                let dstScan = try fastEnumerateEntries(root: dst, checkReadable: false, includeNonRegularEntries: true, rejectSymlinks: true)
                if overwrite != .always {
                    var map: [String: (size: Int64, mtimeSec: TimeInterval)] = [:]
                    map.reserveCapacity(dstScan.entries.count)
                    for d in dstScan.entries where (d.mode & S_IFMT) == S_IFREG {
                        map[normKey(d.relativePath)] = (d.size, d.mtimeSec)
                    }
                    dstLookup = map
                }
            }
        }

        // Mixed-Size Scheduling
        let scheduledEntries: [FileEntry]
        if profile.isFATOrExFAT {
            scheduledEntries = scan.entries
        } else {
            scheduledEntries = scan.entries.sorted { $0.size > $1.size }
        }

        let aggregator = ProgressAggregator(filesTotal: scan.entries.count, bytesTotal: scan.totalBytes, onProgress: onProgress)
        var batchError: Error?
        do {
            try executeCopyBatch(
                entries: scheduledEntries,
                isSingleFile: scan.isSingleFile,
                dstRoot: dst,
                dstExists: dstExistedBefore,
                dstLookup: dstLookup,
                overwrite: overwrite,
                profile: profile,
                preserve: preserve,
                useDirectIO: settings.useDirectIO,
                chunkSize: chunkSize,
                control: control,
                aggregator: aggregator,
                tracker: tracker,
                onConflict: onConflict
            )
        } catch {
            batchError = error
        }

        if control.isCancelled {
            try rollbackCancelledDestination(tracker: tracker)
            throw TransferEngineError.cancelled
        }

        if let err = batchError {
            throw err
        }

        if !scan.isSingleFile && !control.isCancelled {
            for relDir in scan.dirs {
                if control.isCancelled {
                    try rollbackCancelledDestination(tracker: tracker)
                    throw TransferEngineError.cancelled
                }
                let dPath = dst.hasSuffix("/") ? dst + relDir : dst + "/" + relDir
                try mkdirRecursivePOSIX(dPath, dstRoot: dst, tracker: tracker)
            }
        }

        // Layer 2 Post-Transfer Double-Check & Auto-Repair
        if settings.verifyAfterTransfer && !scan.entries.isEmpty {
            do {
                let verifyResult = try verifyAndRepair(
                    srcEntries: scan.entries,
                    isSingleFile: scan.isSingleFile,
                    dstRoot: dst,
                    overwrite: overwrite,
                    dstLookup: dstLookup,
                    singleFilePreexisting: singleFilePreexisting,
                    profile: profile,
                    preserve: preserve,
                    useDirectIO: settings.useDirectIO,
                    chunkSize: chunkSize,
                    control: control,
                    aggregator: aggregator,
                    tracker: tracker
                )
                return aggregator.finish(statusText: "Double-check verified: \(verifyResult)/\(scan.entries.count) files")
            } catch {
                if control.isCancelled {
                    try rollbackCancelledDestination(tracker: tracker)
                    throw TransferEngineError.cancelled
                }
                throw error
            }
        }

        return aggregator.finish(statusText: "Completed \(scan.entries.count) files")
    }

    private static func executeCopyBatch(
        entries: [FileEntry],
        isSingleFile: Bool,
        dstRoot: String,
        dstExists: Bool,
        dstLookup: [String: (size: Int64, mtimeSec: TimeInterval)]?,
        overwrite: OverwriteRule,
        profile: DestinationProfile,
        preserve: Bool,
        useDirectIO: Bool,
        chunkSize: Int,
        control: TransferControl,
        aggregator: ProgressAggregator,
        tracker: RollbackTracker? = nil,
        onConflict: ((FileConflictInfo) -> FileConflictDecision)? = nil
    ) throws {
        guard !entries.isEmpty else { return }

        let workLock = NSLock()
        let dirLock = NSLock()
        var createdDirs: Set<String> = [dstRoot]
        var nextIndex = 0
        var firstError: Error?
        let largeFileSem = profile.isFATOrExFAT ? DispatchSemaphore(value: 2) : nil
        let group = DispatchGroup()
        let workers = min(profile.workerCount, entries.count)
        let queue = DispatchQueue(label: "com.sentor.copy.pool", attributes: .concurrent)

        for _ in 0..<workers {
            group.enter()
            queue.async {
                let alignedBuf = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 4096)
                defer {
                    alignedBuf.deallocate()
                    group.leave()
                }

                while true {
                    if !control.waitIfPaused() {
                        workLock.lock()
                        if firstError == nil { firstError = TransferEngineError.cancelled }
                        workLock.unlock()
                        return
                    }

                    workLock.lock()
                    if firstError != nil || nextIndex >= entries.count {
                        workLock.unlock()
                        return
                    }
                    let entry = entries[nextIndex]
                    nextIndex += 1
                    workLock.unlock()

                    let targetPath: String
                    if isSingleFile {
                        if isDirectoryPOSIX(dstRoot) {
                            targetPath = dstRoot.hasSuffix("/") ? dstRoot + entry.relativePath : dstRoot + "/" + entry.relativePath
                        } else {
                            targetPath = dstRoot
                        }
                    } else {
                        targetPath = dstRoot.hasSuffix("/") ? dstRoot + entry.relativePath : dstRoot + "/" + entry.relativePath
                    }

                    let shouldCopy: Bool
                    if !dstExists || overwrite == .always {
                        shouldCopy = true
                    } else {
                        let existingMeta: (size: Int64, mtimeSec: TimeInterval)?
                        if let lookup = dstLookup {
                            existingMeta = lookup[normKey(entry.relativePath)]
                        } else {
                            var st = stat()
                            if lstat(targetPath, &st) == 0 {
                                let dMtime = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000.0
                                existingMeta = (Int64(st.st_size), dMtime)
                            } else {
                                existingMeta = nil
                            }
                        }

                        if let existing = existingMeta {
                            switch overwrite {
                            case .always:
                                shouldCopy = true
                            case .never:
                                shouldCopy = false
                            case .ask:
                                let info = FileConflictInfo(
                                    relativePath: entry.relativePath,
                                    fileName: (entry.srcPath as NSString).lastPathComponent,
                                    sourceSize: entry.size,
                                    sourceMtime: Date(timeIntervalSince1970: entry.mtimeSec),
                                    destSize: existing.size,
                                    destMtime: Date(timeIntervalSince1970: existing.mtimeSec)
                                )
                                let action = control.resolveConflict(info, handler: onConflict)
                                switch action {
                                case .overwrite:
                                    shouldCopy = true
                                case .skip:
                                    control.markSkipped(normKey(entry.relativePath))
                                    shouldCopy = false
                                case .keepNewer:
                                    if entry.mtimeSec > (existing.mtimeSec + profile.timestampTolerance) {
                                        shouldCopy = true
                                    } else {
                                        control.markSkipped(normKey(entry.relativePath))
                                        shouldCopy = false
                                    }
                                case .cancel:
                                    control.cancel()
                                    workLock.lock()
                                    if firstError == nil { firstError = TransferEngineError.cancelled }
                                    workLock.unlock()
                                    return
                                }
                            }
                        } else {
                            shouldCopy = true
                        }
                    }

                    if !shouldCopy {
                        aggregator.add(bytes: entry.size, files: 1, currentFile: entry.relativePath)
                        continue
                    }

                    // On-demand parent directory creation (with symlink ancestry validation)
                    let parentDir = (targetPath as NSString).deletingLastPathComponent
                    let effectiveDstRoot = isSingleFile ? parentDir : dstRoot
                    dirLock.lock()
                    let needsDir = !createdDirs.contains(parentDir)
                    dirLock.unlock()
                    if needsDir {
                        do {
                            try mkdirRecursivePOSIX(parentDir, dstRoot: effectiveDstRoot, tracker: tracker)
                            dirLock.lock()
                            createdDirs.insert(parentDir)
                            dirLock.unlock()
                        } catch {
                            workLock.lock()
                            if firstError == nil { firstError = error }
                            workLock.unlock()
                            return
                        }
                    }

                    let isLarge = entry.size >= largeFileThreshold
                    if isLarge { largeFileSem?.wait() }
                    defer { if isLarge { largeFileSem?.signal() } }

                    do {
                        try validateNoSymlinksInDestinationAncestry(targetPath: targetPath, dstRoot: effectiveDstRoot)
                        try copySingleFile(
                            entry: entry,
                            dstPath: targetPath,
                            dstRoot: effectiveDstRoot,
                            profile: profile,
                            preserve: preserve,
                            useDirectIO: useDirectIO,
                            chunkSize: chunkSize,
                            alignedBuffer: alignedBuf,
                            control: control,
                            tracker: tracker
                        ) { delta in
                            aggregator.add(bytes: delta, files: 0, currentFile: entry.relativePath)
                        }
                        aggregator.add(bytes: 0, files: 1, currentFile: entry.relativePath)
                    } catch {
                        workLock.lock()
                        if firstError == nil { firstError = error }
                        workLock.unlock()
                        return
                    }
                }
            }
        }

        group.wait()
        if let err = firstError { throw err }
    }

    private static func shouldCopyFileSingle(entry: FileEntry, dstPath: String, rule: OverwriteRule, tolerance: TimeInterval) -> Bool {
        var st = stat()
        guard lstat(dstPath, &st) == 0 else { return true }
        switch rule {
        case .always, .ask: return true
        case .never: return false
        }
    }

    private static func isNonRetryableTransferError(_ error: Error) -> Bool {
        if case TransferEngineError.cancelled = error { return true }
        if case TransferEngineError.ioError(let msg) = error {
            if msg.contains("Security error") || msg.contains("same physical file") || msg.contains("same inode") || msg.contains("Permission denied") {
                return true
            }
        }
        return false
    }

    private static func copySingleFile(
        entry: FileEntry,
        dstPath: String,
        dstRoot: String,
        profile: DestinationProfile,
        preserve: Bool,
        useDirectIO: Bool,
        chunkSize: Int,
        alignedBuffer: UnsafeMutableRawPointer,
        control: TransferControl,
        tracker: RollbackTracker? = nil,
        onChunk: (Int64) -> Void
    ) throws {
        var lastError: Error?
        for attempt in 1...3 {
            if control.isCancelled { throw TransferEngineError.cancelled }
            var reportedThisAttempt: Int64 = 0
            do {
                try copySingleFileAttempt(
                    entry: entry,
                    dstPath: dstPath,
                    dstRoot: dstRoot,
                    profile: profile,
                    preserve: preserve,
                    useDirectIO: useDirectIO,
                    chunkSize: chunkSize,
                    alignedBuffer: alignedBuffer,
                    control: control,
                    tracker: tracker
                ) { delta in
                    reportedThisAttempt += delta
                    onChunk(delta)
                }
                return
            } catch {
                if reportedThisAttempt > 0 {
                    onChunk(-reportedThisAttempt)
                }
                lastError = error
                if control.isCancelled || attempt == 3 || isNonRetryableTransferError(error) {
                    throw error
                }
                var cleanupSt = stat()
                if Darwin.lstat(dstPath, &cleanupSt) == 0 &&
                    (cleanupSt.st_mode & S_IFMT) == S_IFREG &&
                    !samePhysicalObject(entry.srcPath, dstPath) {
                    Darwin.chflags(dstPath, 0)
                    Darwin.lchmod(dstPath, 0o644)
                    Darwin.unlink(dstPath)
                }
                let parent = (dstPath as NSString).deletingLastPathComponent
                try? mkdirRecursivePOSIX(parent, dstRoot: dstRoot, tracker: tracker)
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        if let lastError { throw lastError }
    }

    private static func copySingleFileAttempt(
        entry: FileEntry,
        dstPath: String,
        dstRoot: String,
        profile: DestinationProfile,
        preserve: Bool,
        useDirectIO: Bool,
        chunkSize: Int,
        alignedBuffer: UnsafeMutableRawPointer,
        control: TransferControl,
        tracker: RollbackTracker? = nil,
        onChunk: (Int64) -> Void
    ) throws {
        try validateNoSymlinksInDestinationAncestry(targetPath: dstPath, dstRoot: dstRoot)

        if samePhysicalObject(entry.srcPath, dstPath) {
            throw TransferEngineError.ioError("Source and destination refer to the same physical file (\(dstPath))")
        }

        var dstPreStat = stat()
        let dstExistedPrior = (Darwin.lstat(dstPath, &dstPreStat) == 0)
        if dstExistedPrior {
            let dstType = dstPreStat.st_mode & S_IFMT
            if dstType == S_IFLNK {
                throw TransferEngineError.ioError("Security error: refusing to overwrite symbolic link at destination (\(dstPath))")
            }
            if dstType == S_IFDIR {
                throw TransferEngineError.ioError("Destination path is a directory, expected file (\(dstPath))")
            }
        } else {
            tracker?.recordFile(dstPath)
        }

        if profile.canAPFSClone {
            if dstExistedPrior {
                Darwin.chflags(dstPath, 0)
                Darwin.lchmod(dstPath, 0o644)
                Darwin.unlink(dstPath)
            }
            if Darwin.clonefile(entry.srcPath, dstPath, UInt32(CLONE_NOFOLLOW)) == 0 {
                if preserve {
                    var times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), entry.mtimeSpec]
                    let fd = Darwin.open(dstPath, O_RDONLY | O_NOFOLLOW)
                    if fd >= 0 {
                        Darwin.futimens(fd, &times)
                        Darwin.fchmod(fd, (entry.mode & 0o7777) | 0o200)
                        Darwin.close(fd)
                    }
                }
                onChunk(entry.size)
                return
            }
        }

        let inFd = Darwin.open(entry.srcPath, O_RDONLY)
        guard inFd >= 0 else {
            throw TransferEngineError.ioError("Failed to open source \(entry.srcPath): \(String(cString: strerror(errno)))")
        }
        defer { Darwin.close(inFd) }

        var inStat = stat()
        guard Darwin.fstat(inFd, &inStat) == 0, (inStat.st_mode & S_IFMT) == S_IFREG else {
            throw TransferEngineError.ioError("Source is not a readable regular file (\(entry.srcPath))")
        }

        if dstExistedPrior && dstPreStat.st_dev == inStat.st_dev && dstPreStat.st_ino == inStat.st_ino {
            throw TransferEngineError.ioError("Source and destination refer to the same physical file (\(dstPath))")
        }

        let openFlags: Int32 = O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW
        var outFd = Darwin.open(dstPath, openFlags, 0o644)
        if outFd < 0 && errno == ELOOP {
            throw TransferEngineError.ioError("Security error: destination is a symbolic link (\(dstPath))")
        }
        if outFd < 0 && (errno == EACCES || errno == EPERM) {
            var retrySt = stat()
            if Darwin.lstat(dstPath, &retrySt) == 0 {
                if (retrySt.st_mode & S_IFMT) == S_IFLNK {
                    throw TransferEngineError.ioError("Security error: destination is a symbolic link (\(dstPath))")
                }
                if retrySt.st_dev == inStat.st_dev && retrySt.st_ino == inStat.st_ino {
                    throw TransferEngineError.ioError("Source and destination refer to the same physical file (\(dstPath))")
                }
                Darwin.chflags(dstPath, 0)
                Darwin.lchmod(dstPath, 0o644)
                Darwin.unlink(dstPath)
            }
            outFd = Darwin.open(dstPath, openFlags, 0o644)
        } else if outFd < 0 && errno == ENOENT {
            let parent = (dstPath as NSString).deletingLastPathComponent
            try mkdirRecursivePOSIX(parent, dstRoot: dstRoot, tracker: tracker)
            outFd = Darwin.open(dstPath, openFlags, 0o644)
        }
        guard outFd >= 0 else {
            throw TransferEngineError.ioError("Failed to open destination \(dstPath): \(String(cString: strerror(errno)))")
        }

        var outClosed = false
        defer { if !outClosed { Darwin.close(outFd) } }

        var outStat = stat()
        guard Darwin.fstat(outFd, &outStat) == 0, (outStat.st_mode & S_IFMT) == S_IFREG else {
            throw TransferEngineError.ioError("Destination is not a regular file (\(dstPath))")
        }
        if outStat.st_dev == inStat.st_dev && outStat.st_ino == inStat.st_ino {
            throw TransferEngineError.ioError("Source and destination refer to the same inode (\(dstPath))")
        }

        if entry.size >= preallocateThreshold {
            var store = fstore_t(fst_flags: UInt32(F_ALLOCATECONTIG | F_ALLOCATEALL), fst_posmode: F_PEOFPOSMODE, fst_offset: 0, fst_length: entry.size, fst_bytesalloc: 0)
            if Darwin.fcntl(outFd, F_PREALLOCATE, &store) != 0 {
                store.fst_flags = UInt32(F_ALLOCATEALL)
                _ = Darwin.fcntl(outFd, F_PREALLOCATE, &store)
            }
        }

        if useDirectIO && entry.size >= directIOThreshold {
            _ = Darwin.fcntl(inFd, F_NOCACHE, 1)
            _ = Darwin.fcntl(outFd, F_NOCACHE, 1)
        }

        while true {
            if !control.waitIfPaused() { throw TransferEngineError.cancelled }
            let bytesRead = Darwin.read(inFd, alignedBuffer, chunkSize)
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw TransferEngineError.ioError("Read error on \(entry.srcPath): \(String(cString: strerror(errno)))")
            }
            if bytesRead == 0 { break }

            var writtenTotal = 0
            while writtenTotal < bytesRead {
                let w = Darwin.write(outFd, alignedBuffer.advanced(by: writtenTotal), bytesRead - writtenTotal)
                if w < 0 {
                    if errno == EINTR { continue }
                    throw TransferEngineError.ioError("Write error on \(dstPath): \(String(cString: strerror(errno)))")
                }
                if w == 0 {
                    throw TransferEngineError.ioError("Zero-byte write on \(dstPath)")
                }
                writtenTotal += w
            }
            onChunk(Int64(bytesRead))
        }

        if preserve {
            var times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)), entry.mtimeSpec]
            Darwin.futimens(outFd, &times)
            if !profile.isFATOrExFAT {
                Darwin.fchmod(outFd, (entry.mode & 0o7777) | 0o200)
            }
        }

        // Layer 1 Inline Verification
        var dstStat = stat()
        guard Darwin.fstat(outFd, &dstStat) == 0, Int64(dstStat.st_size) == entry.size else {
            throw TransferEngineError.verificationFailed("\(entry.relativePath) (inline size mismatch)")
        }

        outClosed = true
        if Darwin.close(outFd) != 0 {
            throw TransferEngineError.ioError("Close/flush error on \(dstPath): \(String(cString: strerror(errno)))")
        }
    }

    // MARK: - Layer 2 Post-Transfer Double-Check & Auto-Repair
    private static func verifyAndRepair(
        srcEntries: [FileEntry],
        isSingleFile: Bool,
        dstRoot: String,
        overwrite: OverwriteRule,
        dstLookup: [String: (size: Int64, mtimeSec: TimeInterval)]?,
        singleFilePreexisting: (exists: Bool, mtimeSec: TimeInterval)?,
        profile: DestinationProfile,
        preserve: Bool,
        useDirectIO: Bool,
        chunkSize: Int,
        control: TransferControl,
        aggregator: ProgressAggregator,
        tracker: RollbackTracker? = nil
    ) throws -> Int {
        if control.isCancelled { throw TransferEngineError.cancelled }
        let missingOrMismatched = findMissingOrMismatched(
            srcEntries: srcEntries,
            isSingleFile: isSingleFile,
            dstRoot: dstRoot,
            overwrite: overwrite,
            dstLookup: dstLookup,
            singleFilePreexisting: singleFilePreexisting,
            profile: profile,
            control: control,
            aggregator: aggregator
        )
        if control.isCancelled { throw TransferEngineError.cancelled }
        if !missingOrMismatched.isEmpty {
            try executeCopyBatch(
                entries: missingOrMismatched,
                isSingleFile: isSingleFile,
                dstRoot: dstRoot,
                dstExists: true,
                dstLookup: nil,
                overwrite: .always,
                profile: profile,
                preserve: preserve,
                useDirectIO: useDirectIO,
                chunkSize: chunkSize,
                control: control,
                aggregator: aggregator,
                tracker: tracker
            )
            if control.isCancelled { throw TransferEngineError.cancelled }
            let stillBad = findMissingOrMismatched(
                srcEntries: srcEntries,
                isSingleFile: isSingleFile,
                dstRoot: dstRoot,
                overwrite: overwrite,
                dstLookup: dstLookup,
                singleFilePreexisting: singleFilePreexisting,
                profile: profile,
                control: control,
                aggregator: aggregator
            )
            if control.isCancelled { throw TransferEngineError.cancelled }
            if !stillBad.isEmpty {
                throw TransferEngineError.verificationFailed("\(stillBad.count) file(s) failed double-check (e.g. \(stillBad[0].relativePath))")
            }
        }
        return srcEntries.count
    }

    private static func shouldVerifyEntry(
        _ entry: FileEntry,
        isSingleFile: Bool,
        overwrite: OverwriteRule,
        dstLookup: [String: (size: Int64, mtimeSec: TimeInterval)]?,
        singleFilePreexisting: (exists: Bool, mtimeSec: TimeInterval)?,
        tolerance: TimeInterval,
        control: TransferControl
    ) -> Bool {
        if control.isSkipped(normKey(entry.relativePath)) {
            return false
        }
        switch overwrite {
        case .always, .ask:
            return true
        case .never:
            if isSingleFile {
                return singleFilePreexisting == nil
            }
            return dstLookup?[normKey(entry.relativePath)] == nil
        }
    }

    private static func verifyFileContentMatch(
        entry: FileEntry,
        targetPath: String,
        bufA: UnsafeMutableRawPointer,
        bufB: UnsafeMutableRawPointer,
        bufSize: Int,
        control: TransferControl
    ) -> Bool {
        var st = stat()
        guard Darwin.lstat(targetPath, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              Int64(st.st_size) == entry.size else {
            return false
        }
        if entry.size == 0 { return true }

        let sFd = Darwin.open(entry.srcPath, O_RDONLY)
        guard sFd >= 0 else { return false }
        defer { Darwin.close(sFd) }

        let dFd = Darwin.open(targetPath, O_RDONLY | O_NOFOLLOW)
        guard dFd >= 0 else { return false }
        defer { Darwin.close(dFd) }

        _ = Darwin.fcntl(dFd, F_NOCACHE, 1)

        var sStat = stat()
        var dStat = stat()
        guard Darwin.fstat(sFd, &sStat) == 0,
              Darwin.fstat(dFd, &dStat) == 0,
              (sStat.st_mode & S_IFMT) == S_IFREG,
              (dStat.st_mode & S_IFMT) == S_IFREG,
              Int64(sStat.st_size) == entry.size,
              Int64(dStat.st_size) == entry.size else {
            return false
        }

        var offset: Int64 = 0
        while offset < entry.size {
            if !control.waitIfPaused() {
                return false
            }
            let chunkLen = Int(min(Int64(bufSize), entry.size - offset))
            let sRead = readExact(fd: sFd, buf: bufA, count: chunkLen, offset: off_t(offset))
            let dRead = readExact(fd: dFd, buf: bufB, count: chunkLen, offset: off_t(offset))
            guard sRead == chunkLen, dRead == chunkLen, memcmp(bufA, bufB, chunkLen) == 0 else {
                return false
            }
            offset += Int64(chunkLen)
        }
        return true
    }

    private static func readExact(fd: Int32, buf: UnsafeMutableRawPointer, count: Int, offset: off_t?) -> Int {
        var total = 0
        while total < count {
            let r: Int
            if let off = offset {
                r = Darwin.pread(fd, buf.advanced(by: total), count - total, off + off_t(total))
            } else {
                r = Darwin.read(fd, buf.advanced(by: total), count - total)
            }
            if r < 0 {
                if errno == EINTR { continue }
                return -1
            }
            if r == 0 { break }
            total += r
        }
        return total
    }

    private static func findMissingOrMismatched(
        srcEntries: [FileEntry],
        isSingleFile: Bool,
        dstRoot: String,
        overwrite: OverwriteRule,
        dstLookup: [String: (size: Int64, mtimeSec: TimeInterval)]?,
        singleFilePreexisting: (exists: Bool, mtimeSec: TimeInterval)?,
        profile: DestinationProfile,
        control: TransferControl,
        aggregator: ProgressAggregator
    ) -> [FileEntry] {
        guard !srcEntries.isEmpty else { return [] }

        let dstIsDirSingle = isSingleFile ? isDirectoryPOSIX(dstRoot) : false
        let lock = NSLock()
        var nextIndex = 0
        var checked = 0
        var bad: [FileEntry] = []
        let workers = min(profile.workerCount, srcEntries.count)
        let verifyBufSize = 256 * 1024
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.sentor.verify.pool", attributes: .concurrent)

        for _ in 0..<workers {
            group.enter()
            queue.async {
                let bufA = UnsafeMutableRawPointer.allocate(byteCount: verifyBufSize, alignment: 4096)
                let bufB = UnsafeMutableRawPointer.allocate(byteCount: verifyBufSize, alignment: 4096)
                defer {
                    bufA.deallocate()
                    bufB.deallocate()
                    group.leave()
                }

                while true {
                    if !control.waitIfPaused() {
                        return
                    }
                    lock.lock()
                    if nextIndex >= srcEntries.count {
                        lock.unlock()
                        return
                    }
                    let entry = srcEntries[nextIndex]
                    nextIndex += 1
                    lock.unlock()

                    let ok: Bool
                    if !shouldVerifyEntry(
                        entry,
                        isSingleFile: isSingleFile,
                        overwrite: overwrite,
                        dstLookup: dstLookup,
                        singleFilePreexisting: singleFilePreexisting,
                        tolerance: profile.timestampTolerance,
                        control: control
                    ) {
                        ok = true
                    } else {
                        let targetPath: String
                        if isSingleFile {
                            targetPath = dstIsDirSingle
                                ? (dstRoot.hasSuffix("/") ? dstRoot + entry.relativePath : dstRoot + "/" + entry.relativePath)
                                : dstRoot
                        } else {
                            targetPath = dstRoot.hasSuffix("/") ? dstRoot + entry.relativePath : dstRoot + "/" + entry.relativePath
                        }
                        ok = verifyFileContentMatch(
                            entry: entry,
                            targetPath: targetPath,
                            bufA: bufA,
                            bufB: bufB,
                            bufSize: verifyBufSize,
                            control: control
                        )
                    }

                    lock.lock()
                    checked += 1
                    let c = checked
                    if !ok { bad.append(entry) }
                    lock.unlock()

                    aggregator.reportVerifyProgress(checked: c, total: srcEntries.count)
                }
            }
        }

        group.wait()
        return bad
    }

    // MARK: - Move
    private static func runMove(
        src: String,
        dst: String,
        overwrite: OverwriteRule,
        clone: Bool,
        preserve: Bool,
        settings: SentorSettings,
        control: TransferControl,
        onConflict: ((FileConflictInfo) -> FileConflictDecision)? = nil,
        onProgress: @escaping (TransferTelemetry) -> Void
    ) throws -> TransferTelemetry {
        if !control.waitIfPaused() {
            throw TransferEngineError.cancelled
        }

        if !pathExistsPOSIX(dst) {
            let preScan = try fastEnumerateEntries(root: src, checkReadable: true, followRootSymlink: true)
            if !control.waitIfPaused() {
                throw TransferEngineError.cancelled
            }
            let parent = (dst as NSString).deletingLastPathComponent
            try mkdirRecursivePOSIX(parent, dstRoot: parent)
            if !control.waitIfPaused() {
                throw TransferEngineError.cancelled
            }
            if Darwin.rename(src, dst) == 0 {
                let t = TransferTelemetry(
                    progress: 1.0,
                    filesDone: preScan.entries.count,
                    filesTotal: preScan.entries.count,
                    bytesDone: preScan.totalBytes,
                    bytesTotal: preScan.totalBytes,
                    etaText: "00:00",
                    currentFile: "Double-check verified: \(preScan.entries.count)/\(preScan.entries.count) files"
                )
                onProgress(t)
                return t
            }
        }

        var enforcedSettings = settings
        enforcedSettings.verifyAfterTransfer = true
        let t = try runCopy(src: src, dst: dst, overwrite: overwrite, clone: clone, preserve: preserve, settings: enforcedSettings, control: control, onConflict: onConflict, onProgress: onProgress)
        if control.isCancelled { throw TransferEngineError.cancellationIncomplete }
        try FileManager.default.removeItem(atPath: src)
        return t
    }

    // MARK: - Mirror Sync
    private static func runMirrorSync(
        src: String,
        dst: String,
        overwrite: OverwriteRule,
        clone: Bool,
        preserve: Bool,
        settings: SentorSettings,
        control: TransferControl,
        onConflict: ((FileConflictInfo) -> FileConflictDecision)? = nil,
        onProgress: @escaping (TransferTelemetry) -> Void
    ) throws -> TransferTelemetry {
        if !control.waitIfPaused() {
            throw TransferEngineError.cancelled
        }

        // Validate source readability and destination safety BEFORE any copy or prune operation
        let initialSrcScan = try fastEnumerateEntries(root: src, checkReadable: true, followRootSymlink: true)
        if pathExistsPOSIX(dst) {
            if isSymbolicLinkPOSIX(dst) {
                throw TransferEngineError.ioError("Security error: destination path cannot be a symbolic link (\(dst))")
            }
            _ = try fastEnumerateEntries(root: dst, checkReadable: false, includeNonRegularEntries: true, rejectSymlinks: true)
        }

        let telemetry = try runCopy(src: src, dst: dst, overwrite: overwrite, clone: clone, preserve: preserve, settings: settings, control: control, onConflict: onConflict, onProgress: onProgress)
        if !control.waitIfPaused() {
            throw TransferEngineError.cancelled
        }

        let srcScan = try fastEnumerateEntries(root: src, checkReadable: true, followRootSymlink: true)
        let dstScan = try fastEnumerateEntries(root: dst, checkReadable: false, includeNonRegularEntries: true, rejectSymlinks: true)
        let srcFiles = Set((srcScan.entries + initialSrcScan.entries).map { normKey($0.relativePath) })
        let srcDirs = Set((srcScan.dirs + initialSrcScan.dirs).map { normKey($0) })

        for dEntry in dstScan.entries where !srcFiles.contains(normKey(dEntry.relativePath)) {
            if !control.waitIfPaused() { throw TransferEngineError.cancelled }
            var st = stat()
            if Darwin.lstat(dEntry.srcPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFREG {
                Darwin.chflags(dEntry.srcPath, 0)
                Darwin.lchmod(dEntry.srcPath, 0o644)
            }
            if Darwin.unlink(dEntry.srcPath) != 0 && errno != ENOENT {
                throw TransferEngineError.ioError("Failed to delete \(dEntry.relativePath): \(String(cString: strerror(errno)))")
            }
        }
        for dDir in dstScan.dirs.sorted(by: { $0.count > $1.count }) where !srcDirs.contains(normKey(dDir)) {
            if !control.waitIfPaused() { throw TransferEngineError.cancelled }
            let full = dst.hasSuffix("/") ? dst + dDir : dst + "/" + dDir
            try removeEmptyDirectory(full)
        }
        return telemetry
    }

    // MARK: - Dry-Run Diff
    private static func runDiff(
        src: String,
        dst: String,
        control: TransferControl,
        onProgress: @escaping (TransferTelemetry) -> Void
    ) throws -> TransferTelemetry {
        if !control.waitIfPaused() { throw TransferEngineError.cancelled }
        let srcScan = try fastEnumerateEntries(root: src, checkReadable: true, followRootSymlink: true)
        if !control.waitIfPaused() { throw TransferEngineError.cancelled }
        onProgress(TransferTelemetry(filesTotal: srcScan.entries.count, bytesTotal: srcScan.totalBytes))
        let dstScan = pathExistsPOSIX(dst)
            ? try fastEnumerateEntries(root: dst, checkReadable: false, includeNonRegularEntries: false, rejectSymlinks: true)
            : ScanResult(isSingleFile: false, entries: [], dirs: [], totalBytes: 0)
        var dstMap: [String: FileEntry] = [:]
        dstMap.reserveCapacity(dstScan.entries.count)
        for e in dstScan.entries { dstMap[normKey(e.relativePath)] = e }
        let srcSet = Set(srcScan.entries.map { normKey($0.relativePath) })

        var diffs: [FileDiffItem] = []
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short

        for entry in srcScan.entries {
            if !control.waitIfPaused() { throw TransferEngineError.cancelled }
            let modText = fmt.string(from: Date(timeIntervalSince1970: entry.mtimeSec))
            if let d = dstMap[normKey(entry.relativePath)] {
                if entry.size != d.size {
                    diffs.append(FileDiffItem(relativePath: entry.relativePath, kind: .sizeMismatch, sourceSize: formatBytes(entry.size), destSize: formatBytes(d.size), modifiedDate: modText))
                } else if abs(entry.mtimeSec - d.mtimeSec) > 1.0 {
                    diffs.append(FileDiffItem(relativePath: entry.relativePath, kind: .dateMismatch, sourceSize: formatBytes(entry.size), destSize: formatBytes(d.size), modifiedDate: modText))
                }
            } else {
                diffs.append(FileDiffItem(relativePath: entry.relativePath, kind: .missingInDest, sourceSize: formatBytes(entry.size), destSize: "—", modifiedDate: modText))
            }
        }

        for d in dstScan.entries where !srcSet.contains(normKey(d.relativePath)) {
            let modText = fmt.string(from: Date(timeIntervalSince1970: d.mtimeSec))
            diffs.append(FileDiffItem(relativePath: d.relativePath, kind: .missingInSource, sourceSize: "—", destSize: formatBytes(d.size), modifiedDate: modText))
        }

        let t = TransferTelemetry(
            progress: 1.0,
            filesDone: srcScan.entries.count,
            filesTotal: srcScan.entries.count,
            bytesDone: srcScan.totalBytes,
            bytesTotal: srcScan.totalBytes,
            etaText: "00:00",
            currentFile: "\(diffs.count) differences found",
            diffs: diffs
        )
        onProgress(t)
        return t
    }

    // MARK: - Parallel Delete / Shred
    private static func runDelete(
        target: String,
        shredPass: ShredPassOption,
        workers: Int,
        control: TransferControl,
        onProgress: @escaping (TransferTelemetry) -> Void
    ) throws -> TransferTelemetry {
        if !control.waitIfPaused() { throw TransferEngineError.cancelled }
        let scan = try fastEnumerateEntries(
            root: target,
            checkReadable: false,
            includeNonRegularEntries: true,
            rejectSymlinks: false,
            followRootSymlink: false
        )
        if !control.waitIfPaused() { throw TransferEngineError.cancelled }
        onProgress(TransferTelemetry(filesTotal: scan.entries.count, bytesTotal: scan.totalBytes))
        let aggregator = ProgressAggregator(filesTotal: scan.entries.count, bytesTotal: scan.totalBytes, onProgress: onProgress)

        if !scan.entries.isEmpty {
            let workLock = NSLock()
            var nextIdx = 0
            var firstError: Error?
            let group = DispatchGroup()
            let workerCount = min(max(1, workers), scan.entries.count)
            let queue = DispatchQueue(label: "com.sentor.delete.pool", attributes: .concurrent)

            for _ in 0..<workerCount {
                group.enter()
                queue.async {
                    defer { group.leave() }
                    while true {
                        if !control.waitIfPaused() {
                            workLock.lock()
                            if firstError == nil { firstError = TransferEngineError.cancelled }
                            workLock.unlock()
                            return
                        }
                        workLock.lock()
                        if firstError != nil || nextIdx >= scan.entries.count {
                            workLock.unlock()
                            return
                        }
                        let entry = scan.entries[nextIdx]
                        nextIdx += 1
                        workLock.unlock()

                        var lSt = stat()
                        let hasLstat = (Darwin.lstat(entry.srcPath, &lSt) == 0)
                        let isRegularFile = hasLstat && ((entry.mode & S_IFMT) == S_IFREG) && ((lSt.st_mode & S_IFMT) == S_IFREG)

                        if isRegularFile {
                            Darwin.chflags(entry.srcPath, 0)
                            Darwin.lchmod(entry.srcPath, 0o600)
                            let actualSize = Int64(lSt.st_size)
                            switch shredPass {
                            case .fastUnlink:
                                break
                            case .zeroFill:
                                overwriteFile(path: entry.srcPath, size: actualSize, pattern: 0x00, random: false)
                            case .dodThreePass:
                                overwriteFile(path: entry.srcPath, size: actualSize, pattern: 0x00, random: false)
                                overwriteFile(path: entry.srcPath, size: actualSize, pattern: 0xFF, random: false)
                                overwriteFile(path: entry.srcPath, size: actualSize, pattern: 0x00, random: true)
                            }
                        }

                        if Darwin.unlink(entry.srcPath) != 0 && errno != ENOENT {
                            workLock.lock()
                            if firstError == nil {
                                firstError = TransferEngineError.ioError("Failed to delete \(entry.relativePath): \(String(cString: strerror(errno)))")
                            }
                            workLock.unlock()
                            return
                        }
                        aggregator.add(bytes: entry.size, files: 1, currentFile: entry.relativePath)
                    }
                }
            }
            group.wait()
            if let err = firstError { throw err }
        }

        if !scan.isSingleFile {
            for relDir in scan.dirs.sorted(by: { $0.count > $1.count }) {
                if !control.waitIfPaused() { throw TransferEngineError.cancelled }
                let full = target.hasSuffix("/") ? target + relDir : target + "/" + relDir
                var dirSt = stat()
                if Darwin.lstat(full, &dirSt) == 0 && (dirSt.st_mode & S_IFMT) == S_IFDIR {
                    Darwin.chflags(full, 0)
                    Darwin.lchmod(full, 0o700)
                }
                try removeEmptyDirectory(full)
            }
            if !control.waitIfPaused() { throw TransferEngineError.cancelled }
            var rootSt = stat()
            if Darwin.lstat(target, &rootSt) == 0 && (rootSt.st_mode & S_IFMT) == S_IFDIR {
                Darwin.chflags(target, 0)
                Darwin.lchmod(target, 0o700)
            }
            try removeEmptyDirectory(target)
        }

        return aggregator.finish(statusText: "Deleted \(scan.entries.count) files")
    }

    private static func removeEmptyDirectory(_ path: String) throws {
        if Darwin.rmdir(path) != 0 && errno != ENOENT {
            throw TransferEngineError.ioError("Failed to remove \(path): \(String(cString: strerror(errno)))")
        }
    }

    private static func overwriteFile(path: String, size: Int64, pattern: UInt8, random: Bool) {
        guard size > 0 else { return }
        var lSt = stat()
        guard Darwin.lstat(path, &lSt) == 0, (lSt.st_mode & S_IFMT) == S_IFREG else { return }

        let fd = Darwin.open(path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }

        var fSt = stat()
        guard Darwin.fstat(fd, &fSt) == 0,
              (fSt.st_mode & S_IFMT) == S_IFREG,
              fSt.st_dev == lSt.st_dev,
              fSt.st_ino == lSt.st_ino else {
            return
        }

        let bufSize = min(1024 * 1024, Int(size))
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        if !random {
            buf.initialize(repeating: pattern, count: bufSize)
        }

        var remaining = size
        while remaining > 0 {
            let toWrite = min(Int64(bufSize), remaining)
            if random {
                _ = SecRandomCopyBytes(kSecRandomDefault, Int(toWrite), buf)
            }
            let w = Darwin.write(fd, buf, Int(toWrite))
            if w <= 0 { break }
            remaining -= Int64(w)
        }
        Darwin.fsync(fd)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Fast Parallel Directory Indexing & Compare (getattrlistbulk)
    static func fastIndexDirectory(root: String) -> [String: FastIndexedFile] {
        let normalizedRoot = (root as NSString).expandingTildeInPath
        var st = stat()
        guard Darwin.lstat(normalizedRoot, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            return [:]
        }

        let condition = NSCondition()
        var pendingDirs: [(fullPath: String, relPrefix: String)] = [(normalizedRoot, "")]
        var activeWorkers = 0
        var result: [String: FastIndexedFile] = [:]
        let workerCount = min(8, max(4, ProcessInfo.processInfo.activeProcessorCount))
        let group = DispatchGroup()

        for _ in 0..<workerCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let bufSize = 65_536
                let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
                defer {
                    buffer.deallocate()
                    group.leave()
                }

                while true {
                    condition.lock()
                    while pendingDirs.isEmpty && activeWorkers > 0 {
                        condition.wait()
                    }
                    if pendingDirs.isEmpty && activeWorkers == 0 {
                        condition.unlock()
                        return
                    }
                    let current = pendingDirs.removeLast()
                    activeWorkers += 1
                    condition.unlock()

                    var localFiles: [FastIndexedFile] = []
                    var localSubdirs: [(fullPath: String, relPrefix: String)] = []
                    Self.scanSingleDirectoryBulk(
                        dirPath: current.fullPath,
                        relPrefix: current.relPrefix,
                        buffer: buffer,
                        bufferSize: bufSize,
                        filesOut: &localFiles,
                        subdirsOut: &localSubdirs
                    )

                    condition.lock()
                    for file in localFiles {
                        result[file.relativePath] = file
                    }
                    if !localSubdirs.isEmpty {
                        pendingDirs.append(contentsOf: localSubdirs)
                    }
                    activeWorkers -= 1
                    condition.broadcast()
                    condition.unlock()
                }
            }
        }

        group.wait()
        return result
    }

    private static func scanSingleDirectoryBulk(
        dirPath: String,
        relPrefix: String,
        buffer: UnsafeMutableRawPointer,
        bufferSize: Int,
        filesOut: inout [FastIndexedFile],
        subdirsOut: inout [(fullPath: String, relPrefix: String)]
    ) {
        let fd = Darwin.open(dirPath, O_RDONLY | O_DIRECTORY)
        if fd < 0 { return }
        defer { Darwin.close(fd) }

        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME) | UInt32(ATTR_CMN_OBJTYPE) | UInt32(ATTR_CMN_MODTIME)
        attrList.fileattr = UInt32(ATTR_FILE_DATALENGTH)

        while true {
            let count = Darwin.getattrlistbulk(fd, &attrList, buffer, bufferSize, 0)
            if count == 0 {
                return
            }
            if count < 0 {
                let err = errno
                if err == ENOTSUP || err == EINVAL {
                    scanSingleDirectoryFallback(dirPath: dirPath, relPrefix: relPrefix, filesOut: &filesOut, subdirsOut: &subdirsOut)
                }
                return
            }

            var entryPtr = buffer
            for _ in 0..<Int(count) {
                let recordLength = entryPtr.loadUnaligned(as: UInt32.self)
                if recordLength == 0 { break }
                defer { entryPtr = entryPtr.advanced(by: Int(recordLength)) }

                var fieldPtr = entryPtr.advanced(by: MemoryLayout<UInt32>.size)
                let returned = fieldPtr.loadUnaligned(as: attribute_set_t.self)
                fieldPtr = fieldPtr.advanced(by: MemoryLayout<attribute_set_t>.size)

                if (returned.commonattr & UInt32(ATTR_CMN_ERROR)) != 0 {
                    continue
                }

                var entryName = ""
                if (returned.commonattr & UInt32(ATTR_CMN_NAME)) != 0 {
                    let nameRef = fieldPtr.loadUnaligned(as: attrreference_t.self)
                    let strPtr = fieldPtr.advanced(by: Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                    entryName = String(cString: strPtr)
                    fieldPtr = fieldPtr.advanced(by: MemoryLayout<attrreference_t>.size)
                }

                if entryName.isEmpty || entryName == "." || entryName == ".." {
                    continue
                }

                var objType: UInt32 = 0
                if (returned.commonattr & UInt32(ATTR_CMN_OBJTYPE)) != 0 {
                    objType = fieldPtr.loadUnaligned(as: UInt32.self)
                    fieldPtr = fieldPtr.advanced(by: MemoryLayout<UInt32>.size)
                }

                var mtimeSec: TimeInterval = 0
                if (returned.commonattr & UInt32(ATTR_CMN_MODTIME)) != 0 {
                    let ts = fieldPtr.loadUnaligned(as: timespec.self)
                    mtimeSec = TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000.0
                    fieldPtr = fieldPtr.advanced(by: MemoryLayout<timespec>.size)
                }

                var fileSize: Int64 = 0
                if (returned.fileattr & UInt32(ATTR_FILE_DATALENGTH)) != 0 {
                    fileSize = fieldPtr.loadUnaligned(as: Int64.self)
                }

                let childFull = dirPath.hasSuffix("/") ? dirPath + entryName : dirPath + "/" + entryName
                let childRel = relPrefix.isEmpty ? entryName : relPrefix + "/" + entryName

                if objType == UInt32(VDIR.rawValue) {
                    subdirsOut.append((childFull, childRel))
                } else if objType == UInt32(VREG.rawValue) {
                    filesOut.append(FastIndexedFile(relativePath: childRel, size: fileSize, mtimeSec: mtimeSec))
                }
            }
        }
    }

    private static func scanSingleDirectoryFallback(
        dirPath: String,
        relPrefix: String,
        filesOut: inout [FastIndexedFile],
        subdirsOut: inout [(fullPath: String, relPrefix: String)]
    ) {
        guard let dir = Darwin.opendir(dirPath) else { return }
        defer { Darwin.closedir(dir) }
        let dfd = Darwin.dirfd(dir)
        while let ent = Darwin.readdir(dir) {
            let name = withUnsafePointer(to: ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            var childStat = stat()
            if Darwin.fstatat(dfd, name, &childStat, AT_SYMLINK_NOFOLLOW) != 0 { continue }

            let childFull = dirPath.hasSuffix("/") ? dirPath + name : dirPath + "/" + name
            let childRel = relPrefix.isEmpty ? name : relPrefix + "/" + name
            if (childStat.st_mode & S_IFMT) == S_IFDIR {
                subdirsOut.append((childFull, childRel))
            } else if (childStat.st_mode & S_IFMT) == S_IFREG {
                let sz = Int64(childStat.st_size)
                let mtime = TimeInterval(childStat.st_mtimespec.tv_sec) + TimeInterval(childStat.st_mtimespec.tv_nsec) / 1_000_000_000.0
                filesOut.append(FastIndexedFile(relativePath: childRel, size: sz, mtimeSec: mtime))
            }
        }
    }

    static func compareDirectories(leftRoot: String, rightRoot: String) -> (rows: [CompareFileRow], sameCount: Int, timeDiffCount: Int, diffCount: Int, elapsedMs: Int) {
        let startNs = DispatchTime.now().uptimeNanoseconds
        var leftMap: [String: FastIndexedFile] = [:]
        var rightMap: [String: FastIndexedFile] = [:]

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            leftMap = fastIndexDirectory(root: leftRoot)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            rightMap = fastIndexDirectory(root: rightRoot)
            group.leave()
        }
        group.wait()

        var allKeys = Set(leftMap.keys)
        allKeys.formUnion(rightMap.keys)

        var rows: [CompareFileRow] = []
        rows.reserveCapacity(allKeys.count)
        var sameCount = 0
        var timeDiffCount = 0
        var diffCount = 0

        for key in allKeys {
            let l = leftMap[key]
            let r = rightMap[key]
            let kind: CompareMatchKind
            if let l, let r {
                if abs(l.mtimeSec - r.mtimeSec) <= 1.0 && l.size == r.size {
                    kind = .same
                    sameCount += 1
                } else {
                    kind = .timeDiff
                    timeDiffCount += 1
                }
            } else {
                kind = .diff
                diffCount += 1
            }
            rows.append(CompareFileRow(relativePath: key, kind: kind, leftFile: l, rightFile: r))
        }

        rows.sort {
            if $0.kind != $1.kind {
                return $0.kind < $1.kind
            }
            return $0.relativePath < $1.relativePath
        }

        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000)
        return (rows, sameCount, timeDiffCount, diffCount, elapsedMs)
    }

    // MARK: - Headless CLI
    static func runCLI(arguments: [String]) -> Int32 {
        var mode: TransferMode?
        var paths: [String] = []
        var workers = 16
        var autoTune = true

        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--cli", "--headless", "--silent":
                break
            case "--copy", "-c":
                mode = .copy
            case "--move", "-m":
                mode = .move
            case "--sync", "-s":
                mode = .sync
            case "--diff":
                mode = .diff
            case "--delete", "-d":
                mode = .delete
            case "--workers", "-w":
                if i + 1 < arguments.count, let w = Int(arguments[i + 1]) {
                    workers = min(max(w, 1), 64)
                    autoTune = false
                    i += 1
                }
            default:
                if !arg.hasPrefix("-") {
                    paths.append(arg)
                }
            }
            i += 1
        }

        guard let opMode = mode else {
            fputs("Sentor CLI: specify --copy|-c, --move|-m, --sync|-s, --diff, or --delete|-d\n", stderr)
            return 1
        }

        let src: String
        let dst: String
        if opMode == .delete {
            guard let first = paths.first else {
                fputs("Sentor CLI: --delete requires <target>\n", stderr)
                return 1
            }
            src = first
            dst = ""
        } else {
            guard paths.count >= 2 else {
                fputs("Sentor CLI: requires <src> <dst>\n", stderr)
                return 1
            }
            src = paths[0]
            dst = paths[1]
        }

        var settings = SentorSettings()
        settings.maxParallelFiles = workers
        settings.autoTuneWorkers = autoTune
        let control = TransferControl()

        do {
            let res = try execute(
                mode: opMode,
                sourcePath: src,
                destinationPath: dst,
                overwriteRule: .ask,
                shredPass: .fastUnlink,
                enableBlockClone: true,
                preserveTimestamps: true,
                settings: settings,
                control: control
            ) { _ in }
            print("Sentor CLI [\(opMode.rawValue)] complete: \(res.filesDone)/\(res.filesTotal) files (\(res.bytesDoneText)) - \(res.currentFile)")
            return 0
        } catch {
            fputs("Sentor CLI error: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
