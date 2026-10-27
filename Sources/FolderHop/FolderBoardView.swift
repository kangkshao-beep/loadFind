import SwiftUI
import FolderCore

enum Palette {
    static let accent = Color(red: 0.72, green: 0.43, blue: 0.12)
    static let violet = Color(red: 0.48, green: 0.43, blue: 0.66)
    static let green = Color(red: 0.28, green: 0.54, blue: 0.40)
}

struct FolderBoardView: View {
    @ObservedObject var state: AppState
    @State private var keyboardSelection: String?
    @State private var tilt = PanelTilt.neutral
    @State private var pointerInside = false
    @State private var dragOrigin = PanelTilt.neutral
    @State private var isDragging = false
    @FocusState private var boardFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var keyboardFolders: [FolderRecord] { state.recent }

    var body: some View {
        GeometryReader { geometry in
            SolidCardView(pitch: tilt.pitchDegrees, yaw: tilt.yawDegrees,
                          size: CGSize(width: geometry.size.width - 48, height: geometry.size.height - 48),
                          front: panel, back: cardBack)
                .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.14), radius: 10,
                        x: CGFloat(-tilt.lightHorizontal * 3), y: CGFloat(5 - tilt.lightVertical * 2))
                .padding(24)
                .frame(width: geometry.size.width, height: geometry.size.height)
                // Track the stationary outer rectangle, so tilting never moves
                // the hover boundary or creates a feedback loop at the edges.
                .contentShape(Rectangle())
                .overlay {
                    PanelPointerTracker(hoverChanged: { point in
                        if point == nil && !isDragging && !state.isMovingWindow {
                            updateTilt(.neutral, inside: false)
                        }
                    }, pointerDown: {
                        state.cardPointerDown()
                    }, dragBegan: {
                        dragOrigin = tilt
                        isDragging = true
                        state.cardDragBegan()
                    }, dragChanged: { translation in
                        updateTilt(.dragged(from: dragOrigin, deltaX: translation.x, deltaY: translation.y,
                                            width: geometry.size.width, height: geometry.size.height),
                                   inside: true, dragging: true)
                    }, dragEnded: { inside in
                        isDragging = false
                        state.cardDragEnded()
                        if !inside { updateTilt(.neutral, inside: false) }
                    })
                    .allowsHitTesting(false)
                }
        }
        .frame(minWidth: 388, maxWidth: .infinity, minHeight: 468, maxHeight: .infinity)
        .onPreferenceChange(CardMoveHandleRegionKey.self) { state.moveHandleRegionChanged?($0) }
        .contextMenu {
            Button("翻返正面", systemImage: "rectangle.portrait.rotate") { parkFront() }
            Button("設定…", systemImage: "gearshape") { state.showSettings?() }
            Divider()
            Button("結束 FolderHop") { NSApp.terminate(nil) }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($boardFocused)
        .onExitCommand { boardFocused = false }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.return) {
            if let folder = keyboardFolders.first(where: { $0.path == keyboardSelection }) ?? keyboardFolders.first {
                state.openFolder(folder)
            }
            return .handled
        }
        .onChange(of: reduceMotion) { _, _ in updateTilt(.neutral, inside: false) }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.primary.opacity(0.07)).frame(height: 1).padding(.horizontal, 20)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !state.preferences.trackingEnabled { trackingCard }
                        folderSection(title: "最近去過", symbol: "clock", tint: Palette.violet, records: state.recent,
                                      empty: "你去過嘅資料夾，會喺呢度出現。")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                }
                .scrollIndicators(.hidden)
                .onChange(of: keyboardSelection) { _, selection in
                    if let selection { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(selection, anchor: .center) } }
                }
            }
            if let message = state.message { messageBanner(message) }
            footer
        }
        .frame(minWidth: 340, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background {
            VisualEffectView()
                .overlay {
                    // A light sheen keeps the native blur visible instead of
                    // covering it with a nearly opaque painted surface.
                    LinearGradient(colors: [
                        Color.white.opacity(scheme == .dark ? 0.05 : 0.18),
                        Color.white.opacity(scheme == .dark ? 0.01 : 0.035)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(pointerInside ? 0.12 : 0), .clear],
                                   center: UnitPoint(x: (tilt.lightHorizontal + 1) / 2, y: (tilt.lightVertical + 1) / 2),
                                   startRadius: 0, endRadius: 280)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.20 : 0.55), lineWidth: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06)).padding(1)
                }
                .allowsHitTesting(false)
        }
    }

    private var cardBack: some View {
        Button { if !state.suppressCardClick { parkFront() } } label: {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "folder.fill")
                    .font(.system(size: 49, weight: .medium)).foregroundStyle(Palette.accent)
                    .frame(width: 96, height: 96)
                    .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 27))
                Text("FolderHop").font(.system(size: 29, weight: .semibold, design: .rounded))
                Text("熟路，一撳就到。").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Label("紀錄只留喺呢部 Mac", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("點一下翻返正面").font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                VisualEffectView()
                    .overlay(LinearGradient(colors: [.white.opacity(0.28), Palette.accent.opacity(0.09), .black.opacity(0.07)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.55)))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("卡片背面，點一下翻返正面")
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(Palette.accent.opacity(0.12))
                Image(systemName: "folder.fill")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }.frame(width: 46, height: 46)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("拖動橙色圖示搬動面板")
                .help(state.preferences.lockPosition ? "位置已鎖定，可喺右上角選單取消鎖定" : "按住橙色圖示拖動，就可以搬動面板")
                .onHover { hovering in
                    if hovering && !state.preferences.lockPosition { NSCursor.openHand.set() }
                    else { NSCursor.arrow.set() }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("FolderHop").font(.system(size: 21, weight: .semibold, design: .rounded)).tracking(-0.6)
                Text("熟路，一撳就到。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                Toggle("鎖定位置", isOn: $state.preferences.lockPosition)
                Divider()
                Button("設定…", systemImage: "gearshape") { state.showSettings?() }
                Button("結束 FolderHop") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium)).frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary).help("更多選項").accessibilityLabel("更多選項")
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 21)
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 17)).foregroundStyle(Palette.accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.trackingStatus == .denied ? "畀個許可，就可以自動記低。" : "Finder 去過邊，幫你記低。")
                        .font(.system(size: 12, weight: .semibold))
                    Text(state.trackingStatus == .denied
                         ? "喺系統設定允許 FolderHop 存取 Finder，再撳重試。"
                         : "開啟後，最近去過嘅資料夾會自動出現。紀錄只留喺呢部 Mac。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if state.trackingStatus == .denied {
                    Button("開啟系統設定") { state.openAutomationSettings() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
                }
                Spacer()
                Button {
                    state.setTracking?(true)
                } label: {
                    HStack(spacing: 5) {
                        Text(state.trackingStatus == .denied ? "重試" : "開啟自動紀錄")
                        Image(systemName: "arrow.right")
                    }.font(.system(size: 11, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                }.buttonStyle(.plain).foregroundStyle(.white)
                    .background(Palette.accent, in: Capsule())
            }
        }
        .padding(14)
        .background(Palette.accent.opacity(scheme == .dark ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 5)
    }

    private func folderSection(title: String, symbol: String, tint: Color, records: [FolderRecord], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle(title, symbol: symbol, tint: tint)
            if records.isEmpty {
                Text(empty).font(.system(size: 11)).foregroundStyle(.tertiary)
                    .lineSpacing(3).padding(.horizontal, 12).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
            } else {
                VStack(spacing: 2) { ForEach(records) { folder in row(folder) } }
            }
        }
    }

    private func sectionTitle(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            Spacer()
        }.padding(.horizontal, 10)
    }

    private func row(_ folder: FolderRecord) -> some View {
        FolderRow(state: state, folder: folder, selected: keyboardSelection == folder.path)
            .id(folder.path)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(state.trackingStatus == .recording ? Palette.green : Color.secondary.opacity(0.45))
                .frame(width: 5, height: 5)
            Text(state.trackingStatus.label).font(.system(size: 9))
            Spacer(minLength: 4)
            Image(systemName: "lock.shield").font(.system(size: 10))
                .help("紀錄只留喺呢部 Mac")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24).frame(height: 43)
        .background(.primary.opacity(0.025))
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.06)).frame(height: 1) }
    }

    private func messageBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message).font(.system(size: 11)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { state.message = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).accessibilityLabel("關閉訊息")
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.12))
    }

    private func moveSelection(_ delta: Int) {
        let folders = keyboardFolders
        guard !folders.isEmpty else { return }
        let current = folders.firstIndex { $0.path == keyboardSelection }
        let next = current.map { min(max(0, $0 + delta), folders.count - 1) } ?? (delta > 0 ? 0 : folders.count - 1)
        keyboardSelection = folders[next].path
    }

    private func updateTilt(_ value: PanelTilt, inside: Bool, dragging: Bool = false) {
        guard !reduceMotion else {
            tilt = .neutral
            pointerInside = false
            return
        }
        guard tilt != value || pointerInside != inside else { return }
        if dragging {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                tilt = value
                pointerInside = inside
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.65, dampingFraction: 1)) {
                tilt = value
                pointerInside = inside
            }
        }
    }

    private func parkFront() {
        updateTilt(.neutral, inside: false)
    }
}

private struct FolderRow: View {
    @ObservedObject var state: AppState
    let folder: FolderRecord
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        Button { state.openFolderFromClick(folder) } label: {
            HStack(spacing: 11) {
                Image(nsImage: state.icon(for: folder.path)).resizable().interpolation(.high)
                    .frame(width: 29, height: 29).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(state.displayPath(URL(fileURLWithPath: folder.path).deletingLastPathComponent().path))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(folder.path).accessibilityLabel("開啟 \(folder.name)")
        .background((hovered || selected ? Palette.accent.opacity(0.08) : .clear), in: RoundedRectangle(cornerRadius: 11))
        .onHover { hovered = $0 }
        .contextMenu {
            Button("喺 Finder 開啟", systemImage: "folder") { state.openFolder(folder) }
            Button("喺終端機開啟", systemImage: "terminal") { state.openTerminal(folder) }
            Button("複製路徑", systemImage: "doc.on.doc") { state.copyPath(folder) }
            Divider()
            Button("忽略呢個資料夾…", systemImage: "eye.slash") { state.exclude(folder) }
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 24
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PanelPointerTracker: NSViewRepresentable {
    var hoverChanged: (CGPoint?) -> Void
    var pointerDown: () -> Void
    var dragBegan: () -> Void
    var dragChanged: (CGPoint) -> Void
    var dragEnded: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.hoverChanged = hoverChanged
        view.pointerDown = pointerDown
        view.dragBegan = dragBegan
        view.dragChanged = dragChanged
        view.dragEnded = dragEnded
    }

    final class RotationPan: NSPanGestureRecognizer {
        override func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool { false }
    }

    final class TrackingView: NSView, NSGestureRecognizerDelegate {
        var hoverChanged: ((CGPoint?) -> Void)?
        var pointerDown: (() -> Void)?
        var dragBegan: (() -> Void)?
        var dragChanged: ((CGPoint) -> Void)?
        var dragEnded: ((Bool) -> Void)?
        private var area: NSTrackingArea?
        private var pan: RotationPan?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag],
                owner: self)
            addTrackingArea(area)
            self.area = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
            guard let host = window?.contentView else { return }
            let pan = RotationPan(target: self, action: #selector(handlePan(_:)))
            pan.buttonMask = 1
            // A click is replayed to the button only when the drag fails to begin.
            // A recognized drag never activates a folder on mouse-up.
            pan.delaysPrimaryMouseButtonEvents = true
            pan.delegate = self
            host.addGestureRecognizer(pan)
            self.pan = pan
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { hoverChanged?(nil) }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
            if event.type == .leftMouseDown { pointerDown?() }
            if let window = window as? BoardWindow, window.isMoveHandleEvent(event) { return false }
            let point = convert(event.locationInWindow, from: nil)
            return bounds.insetBy(dx: 8, dy: 8).contains(point)
        }

        @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                dragBegan?()
                dragChanged?(recognizer.translation(in: self))
            case .changed:
                dragChanged?(recognizer.translation(in: self))
            case .ended:
                dragChanged?(recognizer.translation(in: self))
                dragEnded?(bounds.contains(recognizer.location(in: self)))
            case .cancelled:
                dragEnded?(false)
            default: break
            }
        }

        private func report(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            hoverChanged?(bounds.contains(point) ? point : nil)
        }
    }
}
