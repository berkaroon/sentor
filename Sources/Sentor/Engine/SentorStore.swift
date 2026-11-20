import SwiftUI
import Foundation
import Combine

@MainActor
final class SentorStore: ObservableObject {
    static let shared = SentorStore()

    @Published var settings: SentorSettings {
        willSet {
            SentorTheme.setTheme(newValue.themeMode)
        }
        didSet {
            SentorTheme.setTheme(settings.themeMode)
            saveSettings()
            if !isInitializing && isMiniHUDVisible != settings.enableMiniHUD {
                isMiniHUDVisible = settings.enableMiniHUD
            }
        }
    }
    @Published var session: TransferSessionTab = SentorMockData.initialSession {
        didSet {
            saveSessionIfNeeded()
        }
    }
    @Published var queue: [QueueJob] = []
    @Published var history: [HistoryRecord] = []
    @Published var favorites: [FavoriteFolder] = []
    @Published var activeJob: QueueJob?
    @Published var activeTelemetry: TransferTelemetry?
    @Published var isCancelling = false
    @Published var isQueueHeld = false
    @Published var terminalStatus: String?
    @Published var isPaused: Bool = false
    @Published var statusError: String?
    @Published var isMiniHUDVisible: Bool = false {
        didSet {
            if !isInitializing && settings.enableMiniHUD != isMiniHUDVisible {
                settings.enableMiniHUD = isMiniHUDVisible
            }
            NotchHUDController.shared.setVisible(isMiniHUDVisible, store: self)
        }
    }
    @Published var elapsedText: String = "00:00:00"
    @Published var sourcePreviewSizeText: String = "—"
    @Published var sourcePreviewFilesCount: Int = 0
    @Published var isScanningSourcePreview: Bool = false
    @Published var pendingConflict: FileConflictInfo?
    @Published var compareLeftPath: String = ""
    @Published var compareRightPath: String = ""
    @Published var compareRows: [CompareFileRow] = []
    @Published var isComparing: Bool = false
    @Published var compareSummary: (same: Int, timeDiff: Int, diff: Int, elapsedMs: Int)?
    @Published var compareError: String?
    private var conflictSemaphore: DispatchSemaphore?
    private var conflictDecision: FileConflictDecision?
    private var previewSourcePath: String?

    private var activeControl: TransferControl?
    private let appSupportDir: URL
    private var lastSavedSessionState: SavedSessionState?
    private var isInitializing = true
    private var elapsedTimer: Timer?
    private var elapsedSeconds: Int = 0
    private var sourceScanTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        self.appSupportDir = base.appendingPathComponent("Sentor", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)

        if let loaded: SentorSettings = Self.loadJSON(from: appSupportDir.appendingPathComponent("settings.json")) {
            self.settings = loaded
        } else {
            self.settings = SentorSettings()
        }
        SentorTheme.setTheme(self.settings.themeMode)

        self.history = Self.loadJSON(from: appSupportDir.appendingPathComponent("history.json")) ?? []

        if let loadedFavs: [FavoriteFolder] = Self.loadJSON(from: appSupportDir.appendingPathComponent("favorites.json")) {
            self.favorites = loadedFavs
        } else {
            let home = NSHomeDirectory()
            self.favorites = [
                FavoriteFolder(name: "Downloads", path: home + "/Downloads", diskType: "APFS"),
                FavoriteFolder(name: "Documents", path: home + "/Documents", diskType: "APFS"),
                FavoriteFolder(name: "Desktop", path: home + "/Desktop", diskType: "APFS")
            ]
            saveFavorites()
        }

        if let loadedSession: SavedSessionState = Self.loadJSON(from: appSupportDir.appendingPathComponent("session.json")) {
            self.session.mode = loadedSession.mode
            self.session.sourcePath = loadedSession.sourcePath
            self.session.destinationPath = loadedSession.destinationPath
            self.session.overwriteRule = loadedSession.overwriteRule
            self.session.enableBlockClone = loadedSession.enableBlockClone
            self.session.preserveTimestamps = loadedSession.preserveTimestamps

        }
        if PathItemKind.detect(self.session.sourcePath) == .folder {
            self.compareLeftPath = self.session.sourcePath
        }
        if PathItemKind.detect(self.session.destinationPath) == .folder {
            self.compareRightPath = self.session.destinationPath
        }
        self.lastSavedSessionState = currentSavedSessionState()
        self.isInitializing = false

        refreshVolumeInfo()
        refreshSourcePreview()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMiniHUDVisible = self.settings.enableMiniHUD
        }
    }

    private func currentSavedSessionState() -> SavedSessionState {
        SavedSessionState(
            mode: session.mode,
            sourcePath: session.sourcePath,
            destinationPath: session.destinationPath,
            overwriteRule: session.overwriteRule,
            enableBlockClone: session.enableBlockClone,
            preserveTimestamps: session.preserveTimestamps
        )
    }

    private func saveSessionIfNeeded() {
        guard !isInitializing else { return }
        let current = currentSavedSessionState()
        guard current != lastSavedSessionState else { return }
        lastSavedSessionState = current
        Self.saveJSON(current, to: appSupportDir.appendingPathComponent("session.json"))
    }

    func refreshVolumeInfo() {
        let info = TransferEngine.inspectVolumes(
            source: session.sourcePath,
            destination: session.destinationPath,
            mode: session.mode
        )
        session.diskBanner = info.banner
        session.samePhysicalDisk = info.samePhysicalDisk
    }

    func refreshSourcePreview() {
        sourceScanTask?.cancel()
        previewSourcePath = nil
        let path = session.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            isScanningSourcePreview = false
            sourcePreviewSizeText = "—"
            sourcePreviewFilesCount = 0
            return
        }

        isScanningSourcePreview = true
        sourceScanTask = Task.detached(priority: .utility) { [weak self] in
            let result = Self.scanSourcePreviewSync(path: path)
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.session.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines) == path else { return }
                self.previewSourcePath = path
                self.sourcePreviewSizeText = result.sizeText
                self.sourcePreviewFilesCount = result.count
                self.isScanningSourcePreview = false
            }
        }
    }

    nonisolated private static func scanSourcePreviewSync(path: String) -> (sizeText: String, count: Int) {
        var totalBytes: Int64 = 0
        var fileCount = 0

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            if !isDir.boolValue {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? NSNumber {
                    totalBytes = size.int64Value
                    fileCount = 1
                }
            } else {
                let url = URL(fileURLWithPath: path)
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
                if let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: Array(keys),
                    options: []
                ) {
                    for case let fileURL as URL in enumerator {
                        if Task.isCancelled { return ("—", 0) }
                        if let values = try? fileURL.resourceValues(forKeys: keys),
                           values.isRegularFile == true {
                            fileCount += 1
                            totalBytes += Int64(values.fileSize ?? 0)
                        }
                    }
                }
            }
        }

        let formatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return (formatted, fileCount)
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedSeconds = 0
        elapsedText = "00:00:00"
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeJob != nil else { return }
                if !self.isPaused {
                    self.elapsedSeconds += 1
                    let h = self.elapsedSeconds / 3600
                    let m = (self.elapsedSeconds % 3600) / 60
                    let s = self.elapsedSeconds % 60
                    self.elapsedText = String(format: "%02d:%02d:%02d", h, m, s)
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Single transfer runner
    private func draftJob() -> QueueJob {
        let mode = session.mode
        let source = session.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = session.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let srcName = (source as NSString).lastPathComponent
        let dstName = (destination as NSString).lastPathComponent
        return QueueJob(mode: mode, sourcePath: source, destinationPath: destination,
            overwriteRule: session.overwriteRule, shredPass: session.shredPass,
            enableBlockClone: session.enableBlockClone, preserveTimestamps: session.preserveTimestamps,
            title: mode == .delete ? srcName : "\(srcName) → \(dstName)",
            paths: mode == .delete ? source : "\(source) → \(destination)",
            sizeText: previewSourcePath == source && !isScanningSourcePreview ? sourcePreviewSizeText : "—", verifyAfterCopy: settings.verifyAfterTransfer,
            fileCount: previewSourcePath == source && !isScanningSourcePreview ? sourcePreviewFilesCount : nil)
    }

    func toggleStartPause() {
        guard activeControl != nil, !isCancelling else { return }
        isPaused.toggle()
        activeControl?.setPaused(isPaused)
    }

    func startActiveTransfer() {
        guard activeControl == nil else { return }
        if queue.isEmpty { isQueueHeld = false }
        startJob(draftJob())
    }

    private func startJob(_ job: QueueJob) {
        guard activeControl == nil else { return }
        guard !job.sourcePath.isEmpty, job.mode == .delete || !job.destinationPath.isEmpty else {
            statusError = settings.language == .tr ? "Kaynak ve hedef seçin." : "Choose a source and destination."
            terminalStatus = statusError
            recordHistory(mode: job.mode, src: job.sourcePath, dst: job.destinationPath, telemetry: TransferTelemetry(), outcome: .failed, detail: statusError)
            isQueueHeld = true
            return
        }
        if job.mode != .delete {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: (job.destinationPath as NSString).expandingTildeInPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                statusError = settings.language == .tr ? "Hedef klasöre erişilemiyor: \(job.title)" : "Destination folder is unavailable: \(job.title)"
                terminalStatus = statusError
                recordHistory(mode: job.mode, src: job.sourcePath, dst: job.destinationPath, telemetry: TransferTelemetry(), outcome: .failed, detail: statusError)
                isQueueHeld = true
                return
            }
        }
        statusError = nil
        terminalStatus = nil
        isPaused = false
        isCancelling = false
        activeJob = job
        activeTelemetry = nil
        let control = TransferControl()
        activeControl = control
        startElapsedTimer()
        var jobSettings = settings
        jobSettings.verifyAfterTransfer = job.verifyAfterCopy
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try TransferEngine.execute(mode: job.mode, sourcePath: job.sourcePath,
                    destinationPath: job.destinationPath, overwriteRule: job.overwriteRule,
                    shredPass: job.shredPass, enableBlockClone: job.enableBlockClone,
                    preserveTimestamps: job.preserveTimestamps, settings: jobSettings, control: control,
                    onConflict: { [weak self] info in
                        guard let self else { return FileConflictDecision(action: .cancel, applyToAll: false) }
                        let sem = DispatchSemaphore(value: 0)
                        DispatchQueue.main.async {
                            if control.isCancelled {
                                sem.signal()
                                return
                            }
                            self.conflictDecision = nil
                            self.conflictSemaphore = sem
                            self.pendingConflict = info
                        }
                        sem.wait()
                        var decision = FileConflictDecision(action: .cancel, applyToAll: false)
                        let readSem = DispatchSemaphore(value: 0)
                        DispatchQueue.main.async {
                            if let d = self.conflictDecision {
                                decision = d
                            }
                            readSem.signal()
                        }
                        readSem.wait()
                        return decision
                    }) { telemetry in
                    DispatchQueue.main.async {
                        guard let self, self.activeControl === control, !control.isCancelled else { return }
                        self.activeTelemetry = telemetry
                    }
                }
                DispatchQueue.main.async {
                    guard let self, self.activeControl === control else { return }
                    self.activeTelemetry = result
                    self.recordHistory(mode: job.mode, src: job.sourcePath, dst: job.destinationPath, telemetry: result, outcome: .completed)
                    self.terminalStatus = self.settings.language == .tr ? "Tamamlandı: \(job.title)" : "Completed: \(job.title)"
                    self.finishActiveJob()
                    self.startNextQueuedJobIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.activeControl === control else { return }
                    let cancelled: Bool
                    if case TransferEngineError.cancelled = error { cancelled = true } else { cancelled = false }
                    let unsafeCancel: Bool
                    if case TransferEngineError.cancellationIncomplete = error { unsafeCancel = true } else { unsafeCancel = false }
                    let outcome: TransferOutcome = (cancelled || unsafeCancel) ? .cancelled : .failed
                    self.recordHistory(mode: job.mode, src: job.sourcePath, dst: job.destinationPath,
                                       telemetry: self.activeTelemetry ?? TransferTelemetry(), outcome: outcome,
                                       detail: cancelled ? nil : error.localizedDescription)
                    if cancelled {
                        self.terminalStatus = self.settings.language == .tr ? "İptal edildi: \(job.title)" : "Cancelled: \(job.title)"
                    } else {
                        self.statusError = "\(job.title): \(error.localizedDescription)"
                        self.terminalStatus = self.statusError
                        self.isQueueHeld = true
                    }
                    self.finishActiveJob()
                    if cancelled { self.startNextQueuedJobIfNeeded() }
                }
            }
        }
    }

    private func finishActiveJob() {
        stopElapsedTimer()
        activeControl = nil
        activeJob = nil
        isPaused = false
        isCancelling = false
    }

    func resolveConflict(action: FileConflictAction, applyToAll: Bool) {
        conflictDecision = FileConflictDecision(action: action, applyToAll: applyToAll)
        pendingConflict = nil
        conflictSemaphore?.signal()
        conflictSemaphore = nil
    }

    // MARK: - Fast Folder Compare
    func runFolderCompare() {
        let left = (compareLeftPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let right = (compareRightPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath

        var leftIsDir: ObjCBool = false
        var rightIsDir: ObjCBool = false
        guard !left.isEmpty, !right.isEmpty,
              FileManager.default.fileExists(atPath: left, isDirectory: &leftIsDir), leftIsDir.boolValue,
              FileManager.default.fileExists(atPath: right, isDirectory: &rightIsDir), rightIsDir.boolValue else {
            compareError = settings.language == .tr
                ? "Karşılaştırmak için iki geçerli klasör veya disk seçin."
                : "Choose two valid folders or disks to compare."
            return
        }

        compareError = nil
        isComparing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = TransferEngine.compareDirectories(leftRoot: left, rightRoot: right)
            DispatchQueue.main.async {
                guard let self else { return }
                self.compareRows = outcome.rows
                self.compareSummary = (outcome.sameCount, outcome.timeDiffCount, outcome.diffCount, outcome.elapsedMs)
                self.isComparing = false
            }
        }
    }

    func cancelActiveTransfer() {
        guard let control = activeControl, !isCancelling else { return }
        isCancelling = true
        isPaused = false
        control.cancel()
        if conflictSemaphore != nil {
            resolveConflict(action: .cancel, applyToAll: false)
        }
    }

    func enqueueCurrentSession() {
        let job = draftJob()
        guard job.mode == .copy || job.mode == .move,
              !job.sourcePath.isEmpty, !job.destinationPath.isEmpty else { return }
        func same(_ other: QueueJob) -> Bool {
            other.mode == job.mode && (other.sourcePath as NSString).standardizingPath == (job.sourcePath as NSString).standardizingPath &&
            (other.destinationPath as NSString).standardizingPath == (job.destinationPath as NSString).standardizingPath
        }
        guard !queue.contains(where: same), !(activeJob.map(same) ?? false) else {
            statusError = settings.language == .tr ? "Bu aktarım zaten çalışıyor veya kuyrukta." : "This transfer is already active or queued."
            return
        }
        statusError = nil
        queue.append(job)
    }

    func startNextQueuedJobIfNeeded() {
        guard activeControl == nil, !isQueueHeld, !queue.isEmpty else { return }
        // Destructive actions always require an explicit standalone confirmation.
        guard queue[0].mode == .copy || queue[0].mode == .move else { isQueueHeld = true; return }
        let job = queue[0]
        session.mode = job.mode
        session.sourcePath = job.sourcePath
        session.destinationPath = job.destinationPath
        session.overwriteRule = job.overwriteRule
        session.enableBlockClone = job.enableBlockClone
        session.preserveTimestamps = job.preserveTimestamps
        refreshVolumeInfo()
        refreshSourcePreview()
        startJob(job)
        if activeJob?.id == job.id { queue.removeFirst() }
    }

    func holdQueue() { isQueueHeld = true }
    func resumeQueue() { isQueueHeld = false; startNextQueuedJobIfNeeded() }
    func removeQueueJob(_ id: UUID) { queue.removeAll { $0.id == id } }

    // MARK: - History & Favorites Persistence
    private func recordHistory(mode: TransferMode, src: String, dst: String, telemetry: TransferTelemetry, outcome: TransferOutcome, detail: String? = nil) {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        let summary = String(format: "%d files · %@ · %.1f MB/s", telemetry.filesDone, telemetry.bytesDoneText, telemetry.speedMBps)
        let rec = HistoryRecord(
            mode: mode,
            source: src,
            destination: mode == .delete ? "—" : dst,
            summary: summary,
            timestamp: fmt.string(from: Date()),
            isPinned: false,
            outcome: outcome,
            detail: detail
        )
        history.insert(rec, at: 0)
        if history.count > 50 {
            history = Array(history.prefix(50))
        }
        saveHistory()
    }

    func togglePinHistory(_ id: UUID) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            history[idx].isPinned.toggle()
            saveHistory()
        }
    }

    func isFavoritePath(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        return favorites.contains { ($0.path as NSString).standardizingPath == normalized }
    }

    func toggleFavorite(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = (trimmed as NSString).standardizingPath
        if let idx = favorites.firstIndex(where: { ($0.path as NSString).standardizingPath == normalized }) {
            favorites.remove(at: idx)
            saveFavorites()
        } else {
            addFavorite(path: trimmed)
        }
    }

    func addFavorite(path: String) {
        let name = (path as NSString).lastPathComponent
        let info = TransferEngine.inspectVolumes(source: path, destination: "", mode: .delete)
        let disk = info.banner.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? "APFS"
        favorites.append(FavoriteFolder(name: name.isEmpty ? path : name, path: path, diskType: disk))
        saveFavorites()
    }

    func removeFavorite(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    func saveSettings() {
        Self.saveJSON(settings, to: appSupportDir.appendingPathComponent("settings.json"))
    }

    func saveHistory() {
        Self.saveJSON(history, to: appSupportDir.appendingPathComponent("history.json"))
    }

    func saveFavorites() {
        Self.saveJSON(favorites, to: appSupportDir.appendingPathComponent("favorites.json"))
    }

    private static func loadJSON<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
