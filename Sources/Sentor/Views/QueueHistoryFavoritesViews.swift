import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var store: SentorStore
    var onRerun: (HistoryRecord) -> Void
    private var lang: AppLanguage { store.settings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lang == .tr ? "Son İşlemler" : "Recent Operations")
                    .font(SentorTheme.font(size: 18, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)
                Text(lang == .tr ? "\(store.history.count) kayıt" : "\(store.history.count) items")
                    .font(SentorTheme.mono(size: 11))
                    .foregroundColor(SentorTheme.textMuted)
                Spacer()
            }

            if store.history.isEmpty {
                Text(lang == .tr ? "Henüz işlem kaydı yok." : "No operations recorded yet.")
                    .font(SentorTheme.font(size: 13))
                    .foregroundColor(SentorTheme.textMuted)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(SentorTheme.cardIvory)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SentorTheme.borderWarm, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.history) { record in
                            let outcome = record.outcome ?? .completed
                            HStack(spacing: 14) {
                                Text(record.mode.title(lang))
                                    .font(SentorTheme.mono(size: 10.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(record.mode.bgColor)
                                    .foregroundColor(record.mode.fgColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.mode == .delete ? record.source : "\(record.source) → \(record.destination)")
                                        .font(SentorTheme.mono(size: 12))
                                        .foregroundColor(SentorTheme.textCharcoal)
                                        .lineLimit(1)
                                    Text([record.detail, record.summary, record.timestamp].compactMap { $0 }.joined(separator: " · "))
                                        .font(SentorTheme.font(size: 11))
                                        .foregroundColor(SentorTheme.textMuted)
                                }
                                Spacer()

                                Text(outcome.title(lang))
                                    .font(SentorTheme.font(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(outcome == .completed ? SentorTheme.copySageBg :
                                                outcome == .cancelled ? SentorTheme.diffAmberBg : SentorTheme.deleteRoseBg)
                                    .foregroundColor(outcome == .completed ? SentorTheme.copySageFg :
                                                     outcome == .cancelled ? SentorTheme.diffAmberFg : SentorTheme.deleteRoseFg)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Button {
                                    store.togglePinHistory(record.id)
                                } label: {
                                    Image(systemName: record.isPinned ? "pin.fill" : "pin")
                                        .foregroundColor(record.isPinned ? SentorTheme.sageAccent : SentorTheme.textMuted)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onRerun(record)
                                } label: {
                                    Label(lang == .tr ? "Yeniden hazırla" : "Use paths again", systemImage: "arrow.uturn.backward")
                                        .font(SentorTheme.font(size: 11, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(SentorTheme.sageAccent)
                                        .foregroundColor(SentorTheme.sageAccentFg)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(14)
                            .background(SentorTheme.cardIvory)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SentorTheme.borderWarm, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(20)
    }
}

struct FavoritesView: View {
    @ObservedObject var store: SentorStore
    var onUseAsSource: (FavoriteFolder) -> Void
    var onUseAsDest: (FavoriteFolder) -> Void
    private var lang: AppLanguage { store.settings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lang == .tr ? "Favori Klasörler" : "Favorite Folders")
                    .font(SentorTheme.font(size: 18, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)
                Text(lang == .tr ? "\(store.favorites.count) klasör" : "\(store.favorites.count) folders")
                    .font(SentorTheme.mono(size: 11))
                    .foregroundColor(SentorTheme.textMuted)
                Spacer()
                Button(lang == .tr ? "+ Favori Ekle" : "+ Add Favorite") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        store.addFavorite(path: url.path)
                    }
                }
                .buttonStyle(SwissActionButtonStyle(bg: SentorTheme.sageAccent, fg: SentorTheme.sageAccentFg))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(store.favorites) { fav in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(SentorTheme.sageAccent)
                            Text(fav.name)
                                .font(SentorTheme.font(size: 14, weight: .bold))
                                .foregroundColor(SentorTheme.textCharcoal)
                            Spacer()
                            Text(fav.diskType)
                                .font(SentorTheme.mono(size: 10))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(SentorTheme.surfaceLinen)
                                .foregroundColor(SentorTheme.textMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(fav.path)
                            .font(SentorTheme.mono(size: 11))
                            .foregroundColor(SentorTheme.textMuted)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Button(lang == .tr ? "Kaynak Yap" : "Set Source") {
                                onUseAsSource(fav)
                            }
                            .buttonStyle(SwissActionButtonStyle(bg: SentorTheme.copySageBg, fg: SentorTheme.copySageFg))

                            Button(lang == .tr ? "Hedef Yap" : "Set Dest") {
                                onUseAsDest(fav)
                            }
                            .buttonStyle(SwissActionButtonStyle(bg: SentorTheme.surfaceLinen, fg: SentorTheme.textCharcoal))

                            Spacer()

                            Button {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fav.path)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .foregroundColor(SentorTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")

                            Button {
                                store.removeFavorite(fav.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(SentorTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(SentorTheme.cardIvory)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SentorTheme.borderWarm, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer()
        }
        .padding(20)
    }
}

struct SettingsDraftView: View {
    @ObservedObject var store: SentorStore
    private var lang: AppLanguage { store.settings.language }
    private let chunkLabels = ["1 MB", "2 MB", "4 MB", "8 MB", "16 MB"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.settingsTitle(lang))
                    .font(SentorTheme.font(size: 18, weight: .bold))
                    .foregroundColor(SentorTheme.textCharcoal)

                SettingsCard(title: lang == .tr ? "Genel" : "General") {
                    HStack {
                        Text(L10n.appearance(lang))
                            .font(SentorTheme.font(size: 13))
                            .foregroundColor(SentorTheme.textCharcoal)
                        Spacer()
                        Picker("", selection: $store.settings.themeMode) {
                            ForEach(AppThemeMode.allCases) { mode in
                                Text(L10n.themeName(mode, lang)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    HStack {
                        Text(L10n.interfaceLanguage(lang))
                            .font(SentorTheme.font(size: 13))
                            .foregroundColor(SentorTheme.textCharcoal)
                        Spacer()
                        Picker("", selection: $store.settings.language) {
                            ForEach(AppLanguage.allCases) { l in
                                Text(l.displayName).tag(l)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170)
                    }

                    Toggle(lang == .tr ? "Üst Çentikte Mini-HUD Göster" : "Show Notch Mini-HUD", isOn: $store.settings.enableMiniHUD)
                        .tint(SentorTheme.accentWarm)
                        .font(SentorTheme.font(size: 13))
                }

                engineSettings
            }
            .padding(20)
        }
    }

    private var engineSettings: some View {
        SettingsCard(title: lang == .tr ? "Aktarım motoru" : "Transfer engine") {
            Toggle(lang == .tr ? "Aynı fiziksel diskte sırayla çalış" : "Take turns on the same physical disk",
                   isOn: $store.settings.takeTurnsOnSameDisk)
                .tint(SentorTheme.accentWarm)
                .font(SentorTheme.font(size: 13))
            Toggle(lang == .tr ? "Doğrudan I/O Kullan (≥ 256 MB dosyalar)" : "Use Direct / Unbuffered I/O (files ≥ 256 MB)", isOn: $store.settings.useDirectIO)
                .tint(SentorTheme.accentWarm)
                .font(SentorTheme.font(size: 13))
            Toggle(lang == .tr ? "Diske göre paralel işçi sayısını otomatik ayarla" : "Auto-tune parallel workers per drive", isOn: $store.settings.autoTuneWorkers)
                .tint(SentorTheme.accentWarm)
                .font(SentorTheme.font(size: 13))

            HStack {
                Text(lang == .tr ? "Tampon Boyutu" : "Buffer Chunk Size")
                    .font(SentorTheme.font(size: 13))
                Spacer()
                Picker("", selection: $store.settings.chunkSizeIndex) {
                    ForEach(0..<chunkLabels.count, id: \.self) { idx in
                        Text(chunkLabels[idx]).tag(idx)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            HStack {
                Text(lang == .tr ? "Maks. Paralel Dosya: \(store.settings.maxParallelFiles)" : "Max Parallel Files: \(store.settings.maxParallelFiles)")
                    .font(SentorTheme.font(size: 13))
                Slider(
                    value: Binding(
                        get: { Double(store.settings.maxParallelFiles) },
                        set: { store.settings.maxParallelFiles = Int($0) }
                    ),
                    in: 1...64,
                    step: 1
                )
                .tint(SentorTheme.copySageFg)
            }

            HStack {
                Text(lang == .tr ? "Silme Paralel İşçisi: \(store.settings.deleteWorkers)" : "Delete Parallel Workers: \(store.settings.deleteWorkers)")
                    .font(SentorTheme.font(size: 13))
                Slider(
                    value: Binding(
                        get: { Double(store.settings.deleteWorkers) },
                        set: { store.settings.deleteWorkers = Int($0) }
                    ),
                    in: 1...64,
                    step: 1
                )
                .tint(SentorTheme.deleteRoseFg)
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SentorTheme.font(size: 13, weight: .bold))
                .foregroundColor(SentorTheme.textCharcoal)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SentorTheme.cardIvory)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(SentorTheme.borderWarm, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SwissActionButtonStyle: ButtonStyle {
    let bg: Color
    let fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SentorTheme.font(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(fg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct PastelPillButtonStyle: ButtonStyle {
    let bg: Color
    let fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SentorTheme.font(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(fg)
            .clipShape(Capsule())
    }
}
