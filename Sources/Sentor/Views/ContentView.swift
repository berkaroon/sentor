import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var store = SentorStore.shared
    @State private var section: AppSection = .workspace
    @State private var showActiveDetails = true
    @State private var confirmDestructiveAction = false
    @State private var recentDestinations: [String] = []
    @State private var showOverwriteInfo = false
    @State private var showOverwriteMenu = false
    @State private var showShredMenu = false
    @State private var compareFilter: CompareMatchKind? = nil

    private var lang: AppLanguage { store.settings.language }

    private func label(_ turkish: String, _ english: String) -> String {
        lang == .tr ? turkish : english
    }

    private var draftMode: TransferMode { store.session.mode }
    private var isQueueableDraft: Bool { draftMode == .copy || draftMode == .move }
    private var hasDraftPaths: Bool {
        !store.session.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (draftMode == .delete || !store.session.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(SentorTheme.borderWarm)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    switch section {
                    case .workspace:
                        workspaceBody
                    case .compare:
                        compareWorkspaceBody
                    case .history:
                        HistoryView(store: store) { record in
                            store.session.mode = record.mode == .diff ? .copy : record.mode
                            store.session.sourcePath = record.source
                            store.session.destinationPath = record.destination == "—" ? "" : record.destination
                            store.refreshVolumeInfo()
                            store.refreshSourcePreview()
                            section = .workspace
                        }
                    case .favorites:
                        FavoritesView(
                            store: store,
                            onUseAsSource: { fav in
                                store.session.sourcePath = fav.path
                                store.refreshVolumeInfo()
                                store.refreshSourcePreview()
                                section = .workspace
                            },
                            onUseAsDest: { fav in
                                store.session.destinationPath = fav.path
                                store.refreshVolumeInfo()
                                section = .workspace
                            }
                        )
                    case .settings:
                        SettingsDraftView(store: store)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SentorTheme.canvasCream)
            }

            footerBar
        }
        .background(SentorTheme.canvasCream)
        .id(store.settings.themeMode)
        .frame(minWidth: 1080, minHeight: 620)
        .preferredColorScheme(store.settings.themeMode == .oledDark ? .dark : .light)
        .onAppear {
            if draftMode == .diff { store.session.mode = .copy }
            refreshRecentDestinations()
        }
        .onChange(of: store.history.first?.id) { _ in refreshRecentDestinations() }
        .confirmationDialog(startButtonTitle, isPresented: $confirmDestructiveAction, titleVisibility: .visible) {
            Button(startButtonTitle, role: .destructive) {
                guard store.activeJob == nil else { return }
                store.startActiveTransfer()
            }
        } message: {
            if draftMode == .delete {
                Text(label("\(store.session.sourcePath) kalıcı olarak silinecek.",
                           "\(store.session.sourcePath) will be permanently deleted."))
            } else {
                Text(label("\(store.session.sourcePath) → \(store.session.destinationPath). Hedefe özgü dosyalar silinebilir.",
                           "\(store.session.sourcePath) → \(store.session.destinationPath). Files found only at the destination may be deleted."))
            }
        }
        .onChange(of: store.session.sourcePath) { _ in
            store.refreshVolumeInfo()
            store.refreshSourcePreview()
        }
        .onChange(of: store.session.destinationPath) { _ in
            store.refreshVolumeInfo()
        }
        .onChange(of: store.session.mode) { _ in
            store.refreshVolumeInfo()
        }
        .sheet(item: $store.pendingConflict) { conflict in
            FileConflictSheetView(
                conflict: conflict,
                lang: lang,
                onResolve: { action, applyToAll in
                    store.resolveConflict(action: action, applyToAll: applyToAll)
                }
            )
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(spacing: 0) {
            // Top spacing matching workspaceBody's 16pt top margin
            Color.clear.frame(height: 16)

            // Top line aligned with FROM row's top line
            Rectangle()
                .fill(SentorTheme.borderWarm)
                .frame(height: 1)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach([TransferMode.copy, .move, .sync, .delete]) { mode in
                    let isSelected = (section == .workspace && store.session.mode == mode)
                    Button {
                        store.session.mode = mode
                        section = .workspace
                    } label: {
                        HStack(spacing: 10) {
                            Text(mode.title(lang))
                                .font(SentorTheme.font(size: 16.5, weight: .bold))
                                .foregroundColor(isSelected ? SentorTheme.sageAccentFg : SentorTheme.textCharcoal)
                            Spacer()
                            Image(systemName: mode.icon)
                                .font(.system(size: 12.5))
                                .foregroundColor(isSelected ? SentorTheme.sageAccentFg : SentorTheme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(isSelected ? SentorTheme.sageAccent : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)

                    Rectangle()
                        .fill(SentorTheme.borderWarm)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }

                let isCompareSelected = (section == .compare)
                Button {
                    section = .compare
                } label: {
                    HStack(spacing: 10) {
                        Text(AppSection.compare.title(lang))
                            .font(SentorTheme.font(size: 16.5, weight: .bold))
                            .foregroundColor(isCompareSelected ? SentorTheme.sageAccentFg : SentorTheme.textCharcoal)
                        Spacer()
                        Image(systemName: AppSection.compare.icon)
                            .font(.system(size: 12.5))
                            .foregroundColor(isCompareSelected ? SentorTheme.sageAccentFg : SentorTheme.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(isCompareSelected ? SentorTheme.sageAccent : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

                Rectangle()
                    .fill(SentorTheme.borderWarm)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }

            Spacer()

            // Bottom Navigation (no horizontal dividers between items)
            VStack(spacing: 2) {
                sidebarNavButton(
                    section: .history,
                    title: AppSection.history.title(lang),
                    icon: AppSection.history.icon
                )
                sidebarNavButton(
                    section: .favorites,
                    title: AppSection.favorites.title(lang),
                    icon: AppSection.favorites.icon
                )
                sidebarNavButton(
                    section: .settings,
                    title: AppSection.settings.title(lang),
                    icon: AppSection.settings.icon
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 215)
        .background(SentorTheme.canvasCream)
    }

    private func sidebarNavButton(section target: AppSection, title: String, icon: String) -> some View {
        let isSelected = (section == target)
        return Button {
            section = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? SentorTheme.sageAccent : SentorTheme.textMuted)
                    .frame(width: 18)

                Text(title)
                    .font(SentorTheme.font(size: 15, weight: .bold))
                    .foregroundColor(isSelected ? SentorTheme.sageAccent : SentorTheme.textCharcoal)

                Spacer()


            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? SentorTheme.surfaceLinen : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Main Workspace
    private var workspaceBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Top margin matching sidebar's 16pt top spacing
                Color.clear.frame(height: 16)

                // Top 1px line (aligned with sidebar's 01 Copy top line)
                Rectangle()
                    .fill(SentorTheme.borderWarm)
                    .frame(height: 1)

                Text(label("Yeni aktarım", "New transfer"))
                    .font(SentorTheme.font(size: 16, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)

                // Source
                SwissPathRow(
                    label: store.session.mode == .delete
                        ? (lang == .tr ? "HEDEF" : "TARGET")
                        : (lang == .tr ? "KAYNAK" : "FROM"),
                    path: $store.session.sourcePath,
                    chooseTitle: lang == .tr ? "Seç..." : "Choose...",
                    isFavorite: store.isFavoritePath(store.session.sourcePath),
                    showSwap: false,
                    sourceRow: true,
                    lang: lang,
                    onSwap: {},
                    onToggleFavorite: {
                        store.toggleFavorite(path: store.session.sourcePath)
                    }
                )

                // 2. TO Row (hidden in Delete mode)
                if store.session.mode != .delete {
                    Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

                    SwissPathRow(
                        label: lang == .tr ? "HEDEF" : "TO",
                        path: $store.session.destinationPath,
                        chooseTitle: lang == .tr ? "Seç..." : "Choose...",
                        isFavorite: store.isFavoritePath(store.session.destinationPath),
                        showSwap: true,
                        sourceRow: false,
                        lang: lang,
                        recentPaths: recentDestinations,
                        onSwap: {
                            let tmp = store.session.sourcePath
                            store.session.sourcePath = store.session.destinationPath
                            store.session.destinationPath = tmp
                        },
                        onToggleFavorite: {
                            store.toggleFavorite(path: store.session.destinationPath)
                        }
                    )
                }

                Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

                transferTotalsBand
                    .padding(.vertical, 12)

                Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

                policyAndOptionsBar

                Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

                draftActions

                if let error = store.statusError, error != store.terminalStatus {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(SentorTheme.font(size: 12))
                        .foregroundColor(SentorTheme.deleteRoseFg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                if !store.queue.isEmpty {
                    Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)
                    queueTableSection
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Fast Folder Compare Workspace
    private static let compareDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    private var compareWorkspaceBody: some View {
        let canCompare = !store.isComparing &&
            !store.compareLeftPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !store.compareRightPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let leftName = (store.compareLeftPath as NSString).lastPathComponent
        let rightName = (store.compareRightPath as NSString).lastPathComponent

        return VStack(spacing: 0) {
            Color.clear.frame(height: 16)

            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

            HStack {
                Text(AppSection.compare.title(lang))
                    .font(SentorTheme.font(size: 16, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)
                Spacer()
            }
            .padding(.vertical, 10)

            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

            SwissPathRow(
                label: label("SOL", "LEFT"),
                path: $store.compareLeftPath,
                chooseTitle: label("Klasör seç", "Choose folder"),
                isFavorite: store.isFavoritePath(store.compareLeftPath),
                showSwap: false,
                sourceRow: true,
                allowsFiles: false,
                lang: lang,
                onSwap: {},
                onToggleFavorite: { store.toggleFavorite(path: store.compareLeftPath) }
            )

            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

            SwissPathRow(
                label: label("SAĞ", "RIGHT"),
                path: $store.compareRightPath,
                chooseTitle: label("Klasör seç", "Choose folder"),
                isFavorite: store.isFavoritePath(store.compareRightPath),
                showSwap: true,
                sourceRow: false,
                allowsFiles: false,
                lang: lang,
                recentPaths: recentDestinations,
                onSwap: {
                    swap(&store.compareLeftPath, &store.compareRightPath)
                },
                onToggleFavorite: { store.toggleFavorite(path: store.compareRightPath) }
            )

            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

            HStack(spacing: 12) {
                if let summary = store.compareSummary {
                    compareSummaryBadge(title: "same", count: summary.same, kind: .same)
                    compareSummaryBadge(title: "time diff", count: summary.timeDiff, kind: .timeDiff)
                    compareSummaryBadge(title: "diff", count: summary.diff, kind: .diff)
                }

                Spacer()

                Button {
                    compareFilter = nil
                    store.runFolderCompare()
                } label: {
                    HStack(spacing: 8) {
                        if store.isComparing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "rectangle.split.2x1")
                        }
                        Text(store.isComparing ? label("Taranıyor...", "Comparing...") : label("Karşılaştır", "Compare"))
                    }
                    .font(SentorTheme.font(size: 14, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(canCompare ? SentorTheme.sageAccent : SentorTheme.textMuted)
                    .foregroundColor(SentorTheme.sageAccentFg)
                }
                .buttonStyle(.plain)
                .disabled(!canCompare)
            }
            .padding(.vertical, 14)

            if let error = store.compareError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(SentorTheme.font(size: 12))
                    .foregroundColor(SentorTheme.deleteRoseFg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            if store.compareSummary != nil {
                Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

                HStack(spacing: 0) {
                    Text(leftName.isEmpty ? store.compareLeftPath : leftName)
                        .font(SentorTheme.font(size: 12.5, weight: .bold))
                        .foregroundColor(SentorTheme.textCharcoal)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)

                    Rectangle().fill(SentorTheme.borderWarm).frame(width: 1, height: 34)

                    Text(rightName.isEmpty ? store.compareRightPath : rightName)
                        .font(SentorTheme.font(size: 12.5, weight: .bold))
                        .foregroundColor(SentorTheme.textCharcoal)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .background(SentorTheme.surfaceLinen)

                Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

                if store.compareRows.isEmpty {
                    Text(label("Her iki klasörde dosya bulunamadı.", "No files found in either folder."))
                        .font(SentorTheme.font(size: 12))
                        .foregroundColor(SentorTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                    Spacer(minLength: 0)
                } else {
                    let filteredRows = compareFilter == nil
                        ? store.compareRows
                        : store.compareRows.filter { $0.kind == compareFilter }
                    if filteredRows.isEmpty {
                        Text(label("Bu filtrede dosya yok.", "No files match this filter."))
                            .font(SentorTheme.font(size: 12))
                            .foregroundColor(SentorTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                        Spacer(minLength: 0)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredRows) { row in
                                    compareFileRowView(row)
                                    Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)
                                }
                            }
                        }
                        .background(SentorTheme.cardIvory)
                        .overlay(Rectangle().stroke(SentorTheme.borderWarm, lineWidth: 1))
                        .padding(.bottom, 16)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
    }

    private func compareSummaryBadge(title: String, count: Int, kind: CompareMatchKind) -> some View {
        let isSelected = compareFilter == kind
        let isDimmed = compareFilter != nil && !isSelected
        return Button {
            compareFilter = isSelected ? nil : kind
        } label: {
            Text("\(title): \(count)")
                .font(SentorTheme.mono(size: 11))
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(kind.bgColor)
                .foregroundColor(kind.fgColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? kind.fgColor : Color.clear, lineWidth: 1.5)
                )
                .opacity(isDimmed ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func compareFileRowView(_ row: CompareFileRow) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(row.kind.badgeTitle)
                    .font(SentorTheme.mono(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(row.kind.bgColor)
                    .foregroundColor(row.kind.fgColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: 72, alignment: .leading)

                if let left = row.leftFile {
                    Text(row.relativePath)
                        .font(SentorTheme.mono(size: 11.5))
                        .foregroundColor(SentorTheme.textCharcoal)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(TransferEngine.formatBytes(left.size))
                        .font(SentorTheme.mono(size: 11))
                        .foregroundColor(SentorTheme.textMuted)
                    Text(Self.compareDateFormatter.string(from: Date(timeIntervalSince1970: left.mtimeSec)))
                        .font(SentorTheme.mono(size: 10.5))
                        .foregroundColor(SentorTheme.textSubtle)
                        .frame(width: 112, alignment: .trailing)
                } else {
                    Text("—")
                        .font(SentorTheme.mono(size: 11.5))
                        .foregroundColor(SentorTheme.textSubtle)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(SentorTheme.borderWarm).frame(width: 1)

            HStack(spacing: 8) {
                if let right = row.rightFile {
                    Text(row.relativePath)
                        .font(SentorTheme.mono(size: 11.5))
                        .foregroundColor(SentorTheme.textCharcoal)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(TransferEngine.formatBytes(right.size))
                        .font(SentorTheme.mono(size: 11))
                        .foregroundColor(SentorTheme.textMuted)
                    Text(Self.compareDateFormatter.string(from: Date(timeIntervalSince1970: right.mtimeSec)))
                        .font(SentorTheme.mono(size: 10.5))
                        .foregroundColor(SentorTheme.textSubtle)
                        .frame(width: 112, alignment: .trailing)
                } else {
                    Text("—")
                        .font(SentorTheme.mono(size: 11.5))
                        .foregroundColor(SentorTheme.textSubtle)
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func refreshRecentDestinations() {
        var seen: Set<String> = []
        recentDestinations = Array(store.history.lazy.filter { ($0.outcome ?? .completed) == .completed && ($0.mode == .copy || $0.mode == .move || $0.mode == .sync) }
            .map(\.destination)
            .filter { path in
                var isDirectory: ObjCBool = false
                return seen.insert(path).inserted && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }.prefix(5))
    }

    private var draftSummary: String {
        guard !store.session.sourcePath.isEmpty else { return "" }
        if store.isScanningSourcePreview { return label("Boyut hesaplanıyor…", "Calculating size…") }
        guard store.sourcePreviewSizeText != "—" else { return label("Kaynak bulunamadı", "Source not found") }
        let files = NumberFormatter.localizedString(from: NSNumber(value: store.sourcePreviewFilesCount), number: .decimal)
        return "\(store.sourcePreviewSizeText) · \(files) \(label("dosya", "files"))"
    }

    private var transferTotalsBand: some View {
        let job = store.activeJob
        let sizeText: String
        let fileCount: Int?
        if let job {
            sizeText = store.activeTelemetry?.bytesTotalText ?? job.sizeText
            fileCount = store.activeTelemetry?.filesTotal ?? job.fileCount
        } else if store.isScanningSourcePreview || store.sourcePreviewSizeText == "—" {
            sizeText = "—"
            fileCount = nil
        } else {
            sizeText = store.sourcePreviewSizeText
            fileCount = store.sourcePreviewFilesCount
        }
        let countText = fileCount?.formatted() ?? "—"

        let routeTitle: String = {
            if let job {
                return job.title
            }
            let srcTrimmed = store.session.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let dstTrimmed = store.session.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let srcName = srcTrimmed.isEmpty ? "—" : (srcTrimmed as NSString).lastPathComponent
            if draftMode == .delete {
                return srcName.isEmpty ? "—" : srcName
            }
            let dstName = dstTrimmed.isEmpty ? "—" : (dstTrimmed as NSString).lastPathComponent
            if srcName == "—" && dstName == "—" { return "—" }
            return "\(srcName.isEmpty ? srcTrimmed : srcName) → \(dstName.isEmpty ? dstTrimmed : dstName)"
        }()

        return HStack(spacing: 0) {
            totalColumn(sizeText, caption: label("TOPLAM BOYUT", "TOTAL SIZE"))
            totalsDivider
            totalColumn(countText, caption: label("DOSYA", "FILES"))
            totalsDivider
            VStack(alignment: .leading, spacing: 4) {
                Text(routeTitle)
                    .font(SentorTheme.font(size: 16, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(job?.paths ?? routeTitle)
                Text(totalsScope(for: job, showCalculating: sizeText == "—"))
                    .font(SentorTheme.mono(size: 11))
                    .foregroundColor(SentorTheme.sageBarSubtle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
        }
        .foregroundColor(SentorTheme.sageBarFg)
        .frame(height: 86)
        .background(SentorTheme.sageBarBg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(job == nil ? label("Yeni aktarım özeti", "New transfer totals")
                                      : label("Çalışan işlem özeti", "Active job totals"))
    }

    private func totalsScope(for job: QueueJob?, showCalculating: Bool) -> String {
        if let job {
            if showCalculating && !store.isPaused && !store.isCancelling {
                return label("Toplam hesaplanıyor…", "Calculating totals…")
            }
            return activeStatus(for: job.mode)
        }
        return store.isScanningSourcePreview ? label("Boyut hesaplanıyor…", "Calculating size…")
                                            : label("Hazırlanan seçim", "Draft selection")
    }

    private var totalsDivider: some View {
        Rectangle()
            .fill(SentorTheme.sageBarFg.opacity(0.22))
            .frame(width: 1, height: 46)
    }

    private func totalColumn(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SentorTheme.font(size: 30, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(caption)
                .font(SentorTheme.mono(size: 11))
                .foregroundColor(SentorTheme.sageBarSubtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Overwrite Policy & Checkboxes Row
    private var policyAndOptionsBar: some View {
        HStack(alignment: .center, spacing: 0) {
            if store.session.mode == .delete {
                shredModeSelector
                    .padding(.trailing, 16)
                Spacer(minLength: 8)
            } else {
                overwritePolicySelector
                    .padding(.trailing, 16)

                Rectangle().fill(SentorTheme.borderWarm).frame(width: 1, height: 42)

                SageCheckboxToggle(title: label("Doğrula", "Verify"), isOn: $store.settings.verifyAfterTransfer)
                    .frame(maxWidth: .infinity, alignment: .center)

                Rectangle().fill(SentorTheme.borderWarm).frame(width: 1, height: 42)

                SageCheckboxToggle(title: label("Zaman damgasını koru", "Preserve timestamps"),
                                   isOn: $store.session.preserveTimestamps)
                    .frame(maxWidth: .infinity, alignment: .center)

                Rectangle().fill(SentorTheme.borderWarm).frame(width: 1, height: 42)

                SageCheckboxToggle(title: "APFS clone", isOn: $store.session.enableBlockClone)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, 14)
    }

    private var shredModeSelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(lang == .tr ? "Silme modu" : "Shred mode")
                .font(SentorTheme.font(size: 11, weight: .bold))
                .foregroundColor(SentorTheme.textMuted)
            Button {
                showShredMenu.toggle()
            } label: {
                HStack {
                    Text(store.session.shredPass.title(lang))
                        .font(SentorTheme.font(size: 12.5, weight: .semibold))
                        .foregroundColor(SentorTheme.textCharcoal)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SentorTheme.textMuted)
                }
                .padding(.horizontal, 12)
                .frame(width: 215, height: 34)
                .background(SentorTheme.cardIvory)
                .overlay(Rectangle().stroke(SentorTheme.gridStrong, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showShredMenu, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ShredPassOption.allCases) { opt in
                        shredOptionRow(opt)
                    }
                }
                .padding(6)
                .frame(width: 215, alignment: .leading)
                .background(SentorTheme.cardIvory)
            }
        }
    }

    private func shredOptionRow(_ opt: ShredPassOption) -> some View {
        let isSelected = store.session.shredPass == opt
        return Button {
            store.session.shredPass = opt
            showShredMenu = false
        } label: {
            HStack {
                Text(opt.title(lang))
                    .font(SentorTheme.font(size: 12.5, weight: isSelected ? .bold : .regular))
                    .foregroundColor(SentorTheme.textCharcoal)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SentorTheme.sageAccent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SentorTheme.sageAccent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var overwritePolicySelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(lang == .tr ? "Üzerine yazma politikası" : "Overwrite policy")
                    .font(SentorTheme.font(size: 11, weight: .bold))
                    .foregroundColor(SentorTheme.textMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    showOverwriteInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11.5))
                        .foregroundColor(SentorTheme.textMuted)
                }
                .buttonStyle(.plain)
                .onHover { showOverwriteInfo = $0 }
                .popover(isPresented: $showOverwriteInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(OverwriteRule.allCases) { rule in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.title(lang))
                                    .font(SentorTheme.font(size: 12, weight: .bold))
                                    .foregroundColor(SentorTheme.textCharcoal)
                                Text(rule.description(lang))
                                    .font(SentorTheme.font(size: 11.5))
                                    .foregroundColor(SentorTheme.textMuted)
                            }
                        }
                    }
                    .padding(14)
                    .frame(width: 300, alignment: .leading)
                    .background(SentorTheme.cardIvory)
                }
            }

            Button {
                showOverwriteMenu.toggle()
            } label: {
                HStack {
                    Text(store.session.overwriteRule.title(lang))
                        .font(SentorTheme.font(size: 12.5, weight: .semibold))
                        .foregroundColor(SentorTheme.textCharcoal)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SentorTheme.textMuted)
                }
                .padding(.horizontal, 12)
                .frame(width: 215, height: 34)
                .background(SentorTheme.cardIvory)
                .overlay(Rectangle().stroke(SentorTheme.gridStrong, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOverwriteMenu, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(OverwriteRule.allCases) { rule in
                        overwriteOptionRow(rule)
                    }
                }
                .padding(6)
                .frame(width: 215, alignment: .leading)
                .background(SentorTheme.cardIvory)
            }
        }
    }

    private func overwriteOptionRow(_ rule: OverwriteRule) -> some View {
        let isSelected = store.session.overwriteRule == rule
        return Button {
            store.session.overwriteRule = rule
            showOverwriteMenu = false
        } label: {
            HStack {
                Text(rule.title(lang))
                    .font(SentorTheme.font(size: 12.5, weight: isSelected ? .bold : .regular))
                    .foregroundColor(SentorTheme.textCharcoal)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SentorTheme.sageAccent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SentorTheme.sageAccent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var draftActions: some View {
        let willQueue = isQueueableDraft && (store.activeJob != nil || !store.queue.isEmpty)
        return HStack(spacing: 16) {
            if store.activeJob != nil, !draftSummary.isEmpty {
                Text(draftSummary)
                    .font(SentorTheme.mono(size: 12))
                    .foregroundColor(SentorTheme.textMuted)
            }
            Spacer()
            Button {
                if draftMode == .sync || draftMode == .delete {
                    confirmDestructiveAction = true
                } else if willQueue {
                    store.enqueueCurrentSession()
                } else {
                    store.startActiveTransfer()
                }
            } label: {
                Label(willQueue ? label("Kuyruğa ekle", "Add to queue") : startButtonTitle,
                      systemImage: willQueue ? "plus" : "arrow.right")
                    .font(SentorTheme.font(size: 15, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(hasDraftPaths && (isQueueableDraft || (store.activeJob == nil && store.queue.isEmpty))
                                ? SentorTheme.sageAccent : SentorTheme.textMuted)
                    .foregroundColor(SentorTheme.sageAccentFg)
            }
            .buttonStyle(.plain)
            .disabled(!hasDraftPaths || (!isQueueableDraft && (store.activeJob != nil || !store.queue.isEmpty)))
        }
        .padding(.vertical, 16)
    }

    private var startButtonTitle: String {
        switch (store.session.mode, lang) {
        case (.copy, .tr): return "Kopyalamayı Başlat"
        case (.copy, _): return "Start copy"
        case (.move, .tr): return "Taşımayı Başlat"
        case (.move, _): return "Start move"
        case (.sync, .tr): return "Eşitlemeyi Başlat"
        case (.sync, _): return "Start mirror"
        case (.diff, .tr): return "Önizlemeyi Başlat"
        case (.diff, _): return "Start preview"
        case (.delete, .tr): return "Silmeyi Başlat"
        case (.delete, _): return "Start delete"
        }
    }

    private var queueTableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(label("Sırada", "Up next")) · \(store.queue.count)")
                    .font(SentorTheme.font(size: 13, weight: .bold))
                Spacer()
                Button(store.isQueueHeld ? label("Kuyruğa devam et", "Resume queue") : label("Kuyruğu beklet", "Hold queue")) {
                    if store.isQueueHeld {
                        store.resumeQueue()
                    } else {
                        store.holdQueue()
                    }
                }
            }
            ForEach(store.queue) { job in
                HStack(spacing: 12) {
                    Image(systemName: job.mode.icon)
                        .foregroundColor(SentorTheme.textMuted)
                    Text(job.title)
                        .font(SentorTheme.font(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(job.paths)
                    Spacer()
                    if job.sizeText != "—" { Text(job.sizeText).foregroundColor(SentorTheme.textMuted) }
                    Button {
                        store.removeQueueJob(job.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help(label("Kuyruktan kaldır", "Remove from queue"))
                    .accessibilityLabel(label("Kuyruktan kaldır", "Remove from queue"))
                }
                .padding(10)
                .background(SentorTheme.cardIvory)
            }
        }
        .foregroundColor(SentorTheme.textCharcoal)
        .padding(.vertical, 16)
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)
            if let job = store.activeJob {
                activeTransferBar(job)
            } else if let status = store.terminalStatus {
                HStack(spacing: 12) {
                    Text(status)
                        .lineLimit(2)
                    Spacer()
                    if store.isQueueHeld && !store.queue.isEmpty && section != .workspace {
                        Button(label("Kuyruğu göster", "Show queue")) { section = .workspace }
                    }
                    if store.statusError == nil, let last = store.history.first, (last.outcome ?? .completed) == .completed,
                       last.destination != "—", last.mode != .diff {
                        Button(label("Hedefi Finder’da göster", "Show target in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: last.destination)])
                        }
                    }
                    Button(label("Geçmiş", "History")) { section = .history }
                }
                .font(SentorTheme.font(size: 12))
                .foregroundColor(SentorTheme.textCharcoal)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
        .background(SentorTheme.surfaceLinen)
    }

    private var activeDetailsAction: String {
        showActiveDetails ? label("Ayrıntıları gizle", "Hide details") : label("Ayrıntıları göster", "Show details")
    }

    private func activeStatus(for mode: TransferMode) -> String {
        if store.isCancelling { return label("İptal ediliyor", "Cancelling") }
        if store.isPaused { return label("Duraklatıldı", "Paused") }
        switch mode {
        case .copy: return label("Kopyalanıyor", "Copying")
        case .move: return label("Taşınıyor", "Moving")
        case .sync: return label("Eşitleniyor", "Mirroring")
        case .diff: return label("Karşılaştırılıyor", "Comparing")
        case .delete: return label("Siliniyor", "Deleting")
        }
    }

    private func activeTransferBar(_ job: QueueJob) -> some View {
        let telemetry = store.activeTelemetry
        let progress = min(max(telemetry?.progress ?? 0, 0), 1)
        let status = activeStatus(for: job.mode)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(status)
                    .font(SentorTheme.font(size: 12, weight: .bold))
                    .foregroundColor(SentorTheme.sageAccent)
                Text(job.title)
                    .font(SentorTheme.font(size: 14, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(job.paths)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if let telemetry, !store.isCancelling, !store.isPaused, telemetry.speedMBps > 0 {
                    Text(String(format: "%.1f MB/s", telemetry.speedMBps))
                    if telemetry.etaText != "--:--" {
                        Text("\(label("Kalan", "ETA")) \(telemetry.etaText)")
                    }
                }
                if telemetry != nil {
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                }
                Button {
                    showActiveDetails.toggle()
                } label: {
                    Image(systemName: showActiveDetails ? "chevron.down" : "chevron.up")
                }
                .help(activeDetailsAction)
                .accessibilityLabel(activeDetailsAction)
                Button(store.isPaused ? label("Devam et", "Resume") : label("Duraklat", "Pause")) {
                    store.toggleStartPause()
                }
                .disabled(store.isCancelling)
                Button(label("Bu işi iptal et", "Cancel this job")) {
                    store.cancelActiveTransfer()
                }
                .disabled(store.isCancelling)
                .help(store.isQueueHeld || store.queue.isEmpty
                      ? label("Yalnızca çalışan işi iptal eder", "Cancels the current job")
                      : label("Ardından sıradaki iş başlar", "The next job starts afterwards"))
            }
            .font(SentorTheme.font(size: 12))

            Group {
                if telemetry == nil && !store.isPaused && !store.isCancelling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    ProgressView(value: progress)
                        .tint(SentorTheme.sageAccent)
                }
            }
            .accessibilityLabel(label("Aktarım ilerlemesi", "Transfer progress"))

            if showActiveDetails {
                Text(job.paths)
                    .font(SentorTheme.mono(size: 11))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(job.paths)
                    .textSelection(.enabled)
                if let telemetry {
                    HStack(spacing: 14) {
                        Text("\(telemetry.bytesDoneText) / \(telemetry.bytesTotalText)")
                        Text("\(telemetry.filesDone) / \(telemetry.filesTotal) \(label("dosya", "files"))")
                        Text("\(label("Geçen", "Elapsed")) \(store.elapsedText)")
                        Text("\(label("Tepe hız", "Peak")) \(String(format: "%.1f MB/s", telemetry.peakMBps))")
                        Text("\(telemetry.filesPerSec) \(label("dosya/sn", "files/s"))")
                    }
                    Text(telemetry.currentFile)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .font(SentorTheme.mono(size: 11))
        .foregroundColor(SentorTheme.textCharcoal)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

// MARK: - Swiss Grid Path Row
struct SwissPathRow: View {
    let label: String
    @Binding var path: String
    let chooseTitle: String
    let isFavorite: Bool
    let showSwap: Bool
    let sourceRow: Bool
    var allowsFiles: Bool = true
    let lang: AppLanguage
    var recentPaths: [String] = []
    let onSwap: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isDropTargeted = false

    private var folderTitle: String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if !allowsFiles {
                return lang == .tr ? "Klasör veya disk seç" : "Choose a folder or disk"
            }
            return sourceRow ? (lang == .tr ? "Dosya veya klasör bırak" : "Drop a file or folder")
                             : (lang == .tr ? "Hedef klasör seç" : "Choose a destination folder")
        }
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? trimmed : last
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(SentorTheme.mono(size: 11))
                .foregroundColor(SentorTheme.textMuted)
                .frame(width: 58, alignment: .leading)

            Rectangle()
                .fill(SentorTheme.borderWarm)
                .frame(width: 1, height: 36)

            Image(systemName: PathItemKind.detect(path) == .file ? "doc" : "folder")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(SentorTheme.textCharcoal)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(folderTitle)
                    .font(SentorTheme.font(size: 20, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)
                    .lineLimit(1)

                TextField(label, text: $path)
                    .textFieldStyle(.plain)
                    .font(SentorTheme.mono(size: 12))
                    .foregroundColor(SentorTheme.textMuted)
            }

            Spacer(minLength: 12)

            if showSwap {
                Button(action: onSwap) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13))
                        .foregroundColor(SentorTheme.textMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Swap Source & Destination")
            }

            if !recentPaths.isEmpty {
                Menu(lang == .tr ? "Son hedefler" : "Recent targets") {
                    ForEach(recentPaths, id: \.self) { recent in
                        Button(recent) { path = recent }
                    }
                }
                .fixedSize()
            }

            Button(chooseTitle, action: openPanel)
                .font(SentorTheme.font(size: 12, weight: .bold))
                .frame(width: 100, height: 32)
                .background(SentorTheme.cardIvory)
                .foregroundColor(SentorTheme.textCharcoal)
                .overlay(Rectangle().stroke(SentorTheme.gridStrong, lineWidth: 1))
                .buttonStyle(.plain)

            if !path.isEmpty {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(isFavorite ? SentorTheme.sageAccent : SentorTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help(lang == .tr ? "Favori olarak işaretle" : "Toggle favorite")
            }
        }
        .padding(.vertical, 16)
        .background(isDropTargeted ? SentorTheme.surfaceLinen.opacity(0.6) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard providers.count == 1, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, (sourceRow && allowsFiles) || PathItemKind.detect(url.path) == .folder {
                    DispatchQueue.main.async {
                        self.path = url.path
                    }
                }
            }
            return true
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = sourceRow && allowsFiles
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

// MARK: - Swiss Square Checkbox Toggle
struct SageCheckboxToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle()
                        .fill(isOn ? SentorTheme.sageAccent : SentorTheme.cardIvory)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Rectangle()
                                .stroke(isOn ? SentorTheme.sageAccent : SentorTheme.gridStrong, lineWidth: 1.2)
                        )
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SentorTheme.sageAccentFg)
                    }
                }
                Text(title)
                    .font(SentorTheme.font(size: 13.5, weight: .semibold))
                    .foregroundColor(SentorTheme.textCharcoal)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Windows-Style File Conflict Comparison Sheet
struct FileConflictSheetView: View {
    let conflict: FileConflictInfo
    let lang: AppLanguage
    let onResolve: (FileConflictAction, Bool) -> Void

    @State private var applyToAll = false

    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(SentorTheme.sageAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang == .tr ? "Dosya Zaten Mevcut" : "File Already Exists")
                        .font(SentorTheme.font(size: 16, weight: .bold))
                        .foregroundColor(SentorTheme.textCharcoal)
                    Text(conflict.relativePath)
                        .font(SentorTheme.mono(size: 11.5))
                        .foregroundColor(SentorTheme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

            HStack(spacing: 14) {
                conflictCard(
                    title: lang == .tr ? "Kaynak (Yeni)" : "Source (Incoming)",
                    size: conflict.sourceSize,
                    date: conflict.sourceMtime,
                    highlight: conflict.sourceMtime > conflict.destMtime
                )
                conflictCard(
                    title: lang == .tr ? "Hedef (Mevcut)" : "Destination (Existing)",
                    size: conflict.destSize,
                    date: conflict.destMtime,
                    highlight: conflict.destMtime > conflict.sourceMtime
                )
            }

            SageCheckboxToggle(
                title: lang == .tr ? "Tüm çakışmalara uygula" : "Apply to all conflicts",
                isOn: $applyToAll
            )

            Rectangle().fill(SentorTheme.borderWarm).frame(height: 1)

            HStack(spacing: 10) {
                Button(lang == .tr ? "İptal" : "Cancel") {
                    onResolve(.cancel, false)
                }
                .font(SentorTheme.font(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(SentorTheme.deleteRoseBg)
                .foregroundColor(SentorTheme.deleteRoseFg)
                .overlay(Rectangle().stroke(SentorTheme.deleteRoseFg.opacity(0.35), lineWidth: 1))
                .buttonStyle(.plain)

                Spacer()

                Button(lang == .tr ? "Atla" : "Skip") {
                    onResolve(.skip, applyToAll)
                }
                .font(SentorTheme.font(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(SentorTheme.cardIvory)
                .foregroundColor(SentorTheme.textCharcoal)
                .overlay(Rectangle().stroke(SentorTheme.borderWarm, lineWidth: 1))
                .buttonStyle(.plain)

                Button(lang == .tr ? "Günceli Koru" : "Keep Newer") {
                    onResolve(.keepNewer, applyToAll)
                }
                .font(SentorTheme.font(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(SentorTheme.surfaceLinen)
                .foregroundColor(SentorTheme.textCharcoal)
                .overlay(Rectangle().stroke(SentorTheme.gridStrong, lineWidth: 1))
                .buttonStyle(.plain)

                Button(lang == .tr ? "Üzerine Yaz" : "Overwrite") {
                    onResolve(.overwrite, applyToAll)
                }
                .font(SentorTheme.font(size: 12, weight: .bold))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(SentorTheme.sageAccent)
                .foregroundColor(SentorTheme.sageAccentFg)
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(SentorTheme.canvasCream)
    }

    private func conflictCard(title: String, size: Int64, date: Date, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(SentorTheme.font(size: 11.5, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)
                Spacer()
                if highlight {
                    Text(lang == .tr ? "Daha Yeni" : "Newer")
                        .font(SentorTheme.mono(size: 9.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SentorTheme.sageAccent)
                        .foregroundColor(SentorTheme.sageAccentFg)
                }
            }
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(SentorTheme.font(size: 15, weight: .bold))
                .foregroundColor(SentorTheme.textCharcoal)
            Text(dateFormatter.string(from: date))
                .font(SentorTheme.mono(size: 11))
                .foregroundColor(SentorTheme.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SentorTheme.cardIvory)
        .overlay(Rectangle().stroke(highlight ? SentorTheme.sageAccent : SentorTheme.borderWarm, lineWidth: 1))
    }
}
