import SwiftUI
import AppKit

@MainActor
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 172),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isFloatingPanel = true
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

@MainActor
final class NotchHUDController: ObservableObject {
    static let shared = NotchHUDController()

    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 32
    @Published var isPresented: Bool = false
    @Published var isHovered: Bool = false

    var compactWidth: CGFloat { max(notchWidth + 216, 436) }
    var expandedWidth: CGFloat { max(notchWidth + 300, 520) }
    var compactHeight: CGFloat { notchHeight }
    var expandedHeight: CGFloat { notchHeight + 104 }

    private var panel: NotchPanel?
    private var screenObserver: NSObjectProtocol?
    private var hideWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var globalMouseMonitor: Any?
    nonisolated(unsafe) private var localMouseMonitor: Any?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPanel()
            }
        }
    }

    deinit {
        if let g = globalMouseMonitor {
            NSEvent.removeMonitor(g)
        }
        if let l = localMouseMonitor {
            NSEvent.removeMonitor(l)
        }
    }

    func setVisible(_ visible: Bool, store: SentorStore) {
        if visible {
            hideWorkItem?.cancel()
            hideWorkItem = nil

            let wasHidden = (panel == nil) || !(panel?.isVisible ?? false)
            if panel == nil {
                let p = NotchPanel()
                let root = NotchHUDContentView(store: store, controller: self)
                let hosting = NSHostingView(rootView: root)
                hosting.sizingOptions = []
                if #available(macOS 13.3, *) {
                    hosting.safeAreaRegions = []
                }
                hosting.wantsLayer = true
                hosting.layer?.backgroundColor = NSColor.clear.cgColor
                p.contentView = hosting
                panel = p
            }

            if wasHidden {
                isPresented = false
                isHovered = false
                panel?.ignoresMouseEvents = true
            }

            repositionPanel()
            panel?.orderFrontRegardless()
            repositionPanel()
            startMouseMonitors()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.44, dampingFraction: 0.76)) {
                    self.isPresented = true
                }
                self.updateHoverState()
            }
        } else {
            hideWorkItem?.cancel()
            stopMouseMonitors()
            isHovered = false
            panel?.ignoresMouseEvents = true
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                self.isPresented = false
            }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.panel?.orderOut(nil)
                }
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: work)
        }
    }

    private func startMouseMonitors() {
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateHoverState()
                }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] event in
                Task { @MainActor in
                    self?.updateHoverState()
                }
                return event
            }
        }
    }

    private func stopMouseMonitors() {
        if let g = globalMouseMonitor {
            NSEvent.removeMonitor(g)
            globalMouseMonitor = nil
        }
        if let l = localMouseMonitor {
            NSEvent.removeMonitor(l)
            localMouseMonitor = nil
        }
    }

    @MainActor
    private func updateHoverState() {
        guard isPresented, let panel, panel.isVisible else {
            if isHovered {
                isHovered = false
            }
            panel?.ignoresMouseEvents = true
            return
        }

        let mouse = NSEvent.mouseLocation
        let pf = panel.frame
        let hitRect: NSRect
        if isHovered {
            hitRect = NSRect(
                x: pf.midX - expandedWidth / 2.0,
                y: pf.maxY - expandedHeight,
                width: expandedWidth,
                height: expandedHeight + 4
            )
        } else {
            hitRect = NSRect(
                x: pf.midX - compactWidth / 2.0,
                y: pf.maxY - compactHeight,
                width: compactWidth,
                height: compactHeight + 4
            )
        }

        let shouldHover = hitRect.contains(mouse)
        panel.ignoresMouseEvents = !shouldHover
        if shouldHover != isHovered {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                self.isHovered = shouldHover
            }
        }
    }

    func repositionPanel() {
        guard let screen = NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let screenFrame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        notchHeight = max(32, safeTop)

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            notchWidth = max(160, right.minX - left.maxX)
        } else {
            notchWidth = 185
        }

        let panelWidth: CGFloat = max(540, notchWidth + 320)
        let panelHeight: CGFloat = max(172, notchHeight + 132)
        let originX = screenFrame.midX - (panelWidth / 2.0)
        let originY = screenFrame.maxY - panelHeight

        panel?.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: true)
    }
}

struct NotchShape: Shape {
    var earRadius: CGFloat = 10
    var bottomRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        // Top-left outer ear tip
        path.move(to: CGPoint(x: left, y: top))
        path.addQuadCurve(
            to: CGPoint(x: left + earRadius, y: top + earRadius),
            control: CGPoint(x: left + earRadius, y: top)
        )
        // Left vertical wall to bottom-left corner
        path.addLine(to: CGPoint(x: left + earRadius, y: bottom - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: left + earRadius + bottomRadius, y: bottom),
            control: CGPoint(x: left + earRadius, y: bottom)
        )
        // Bottom edge
        path.addLine(to: CGPoint(x: right - earRadius - bottomRadius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: right - earRadius, y: bottom - bottomRadius),
            control: CGPoint(x: right - earRadius, y: bottom)
        )
        // Right vertical wall up to top-right ear
        path.addLine(to: CGPoint(x: right - earRadius, y: top + earRadius))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top),
            control: CGPoint(x: right - earRadius, y: top)
        )
        path.closeSubpath()
        return path
    }
}

struct NotchBorderShape: Shape {
    var earRadius: CGFloat = 10
    var bottomRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        // Left wall, bottom corners, bottom edge, right wall (never along top y = 0)
        path.move(to: CGPoint(x: left + earRadius, y: top + earRadius))
        path.addLine(to: CGPoint(x: left + earRadius, y: bottom - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: left + earRadius + bottomRadius, y: bottom),
            control: CGPoint(x: left + earRadius, y: bottom)
        )
        path.addLine(to: CGPoint(x: right - earRadius - bottomRadius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: right - earRadius, y: bottom - bottomRadius),
            control: CGPoint(x: right - earRadius, y: bottom)
        )
        path.addLine(to: CGPoint(x: right - earRadius, y: top + earRadius))
        return path
    }
}

struct NotchHUDContentView: View {
    @ObservedObject var store: SentorStore
    @ObservedObject var controller: NotchHUDController
    @State private var pulse = false

    private var lang: AppLanguage { store.settings.language }
    private var expanded: Bool { controller.isHovered }
    private var notchWidth: CGFloat { controller.notchWidth }
    private var notchHeight: CGFloat { controller.notchHeight }

    private var containerWidth: CGFloat {
        guard controller.isPresented else { return notchWidth }
        return expanded ? controller.expandedWidth : controller.compactWidth
    }

    private var containerHeight: CGFloat {
        guard controller.isPresented else { return notchHeight }
        return expanded ? controller.expandedHeight : controller.compactHeight
    }

    private var accentGreen: Color { Color(hex: 0xA8C9A3) }
    private var accentPeach: Color { Color(hex: 0xEAB093) }

    private var playPauseLabel: String {
        store.isPaused ? (lang == .tr ? "Devam" : "Resume") : L10n.pause(lang)
    }

    private var active: Bool { store.activeJob != nil }
    private var transferring: Bool { active && !store.isPaused && !store.isCancelling }
    private var telemetry: TransferTelemetry { store.activeTelemetry ?? TransferTelemetry() }
    private var statusTitle: String {
        if store.isCancelling { return lang == .tr ? "İptal ediliyor" : "Cancelling" }
        if store.isPaused { return lang == .tr ? "Duraklatıldı" : "Paused" }
        return store.activeJob?.mode.title(lang) ?? (lang == .tr ? "Sentor hazır" : "Sentor ready")
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Top Notch Wing Row (exact height of hardware notch)
                HStack(spacing: 0) {
                    // Left Wing
                    HStack(spacing: 6) {
                        CentaurLogoView(size: 16, showBadge: false)
                        Circle()
                            .fill(transferring ? accentGreen : Color(hex: 0xD98A66))
                            .frame(width: 6, height: 6)
                            .scaleEffect(transferring && pulse ? 1.35 : 1.0)
                            .animation(
                                transferring
                                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                                    : .default,
                                value: pulse
                            )
                        Text(statusTitle)
                            .font(SentorTheme.font(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .opacity(controller.isPresented ? 1.0 : 0.0)
                    .offset(x: controller.isPresented ? 0 : 18)

                    // Center hardware notch cutout spacer (+12pt clearance)
                    Spacer()
                        .frame(width: notchWidth + 12)

                    // Right Wing
                    HStack(spacing: 6) {
                        Text(active ? "\(Int(telemetry.progress * 100))%" : "—")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(active ? accentGreen : accentPeach)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(transferring && telemetry.speedMBps > 0 ? String(format: "%.1f MB/s", telemetry.speedMBps) : "—")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if controller.isHovered {
                            Button {
                                store.isMiniHUDVisible = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                            .help(lang == .tr ? "Mini-HUD Kapat" : "Close Mini-HUD")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)
                    .opacity(controller.isPresented ? 1.0 : 0.0)
                    .offset(x: controller.isPresented ? 0 : -18)
                }
                .frame(height: notchHeight)

                // Expanded Drawer Tray
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(store.activeJob?.title ?? store.terminalStatus ?? statusTitle)
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.65))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            if active {
                                Text("\(telemetry.filesDone)/\(telemetry.filesTotal)")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.75))
                                    .lineLimit(1)
                            }

                            if !store.queue.isEmpty {
                                Text(lang == .tr ? "\(store.queue.count) sırada" : "\(store.queue.count) queued")
                                    .font(SentorTheme.font(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: 0x1C1815))
                                    .foregroundColor(accentPeach)
                                    .clipShape(Capsule())
                            }
                        }

                        if active {
                            ProgressView(value: min(max(telemetry.progress, 0), 1))
                                .tint(accentGreen)
                        }

                        HStack(spacing: 8) {
                            if active {
                                Text("\(telemetry.bytesDoneText) / \(telemetry.bytesTotalText)")
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            if active {
                                Button {
                                    store.toggleStartPause()
                                } label: {
                                    Label(playPauseLabel, systemImage: store.isPaused ? "play.fill" : "pause.fill")
                                        .font(SentorTheme.font(size: 10, weight: .bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: 0x182417))
                                        .foregroundColor(accentGreen)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isCancelling)

                                Button {
                                    store.cancelActiveTransfer()
                                } label: {
                                    Label(lang == .tr ? "Bu işi iptal et" : "Cancel this job", systemImage: "xmark")
                                        .font(SentorTheme.font(size: 10, weight: .bold))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: 0x2A161A))
                                        .foregroundColor(Color(hex: 0xE4A3AE))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isCancelling)
                            }

                            Button {
                                AppDelegate.showMainWindow()
                            } label: {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(lang == .tr ? "Sentor Penceresini Aç" : "Open Sentor Window")

                            Button {
                                store.isMiniHUDVisible = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.7))
                                    .padding(5)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(lang == .tr ? "Mini-HUD Kapat" : "Close Mini-HUD")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: containerWidth, height: containerHeight, alignment: .top)
            .clipShape(NotchShape())
            .background(
                NotchShape()
                    .fill(Color.black)
                    .overlay(
                        NotchBorderShape()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .scaleEffect(
                x: controller.isPresented ? 1.0 : 0.86,
                y: controller.isPresented ? 1.0 : 0.72,
                anchor: .top
            )
            .opacity(controller.isPresented ? 1.0 : 0.0)
            .blur(radius: controller.isPresented ? 0.0 : 5.0)
            .animation(.spring(response: 0.44, dampingFraction: 0.76), value: controller.isPresented)
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: expanded)
            .onAppear {
                pulse = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }
}
