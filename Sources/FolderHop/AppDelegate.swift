import AppKit
import SwiftUI
import FolderCore

final class DesktopHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class BoardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var moveHandleRegion: [CGPoint] = []
    var movingChanged: ((Bool) -> Void)?
    private var grabPoint: NSPoint?
    private var cursorPushed = false

    func isMoveHandleEvent(_ event: NSEvent) -> Bool {
        guard moveHandleRegion.count == 4 else { return false }
        let path = CGMutablePath()
        path.addLines(between: moveHandleRegion)
        path.closeSubpath()
        let point = CGPoint(x: event.locationInWindow.x, y: frame.height - event.locationInWindow.y)
        return path.contains(point)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, isMovable, isMoveHandleEvent(event) {
            grabPoint = event.locationInWindow
            movingChanged?(true)
            NSCursor.closedHand.push()
            cursorPushed = true
            return
        }
        if event.type == .leftMouseDragged, grabPoint != nil {
            moveWindow(with: event)
            return
        }
        if event.type == .leftMouseUp, grabPoint != nil {
            moveWindow(with: event)
            saveFrame(usingName: "FolderHop.Desktop")
            grabPoint = nil
            movingChanged?(false)
            if cursorPushed { NSCursor.pop(); cursorPushed = false }
            return
        }
        super.sendEvent(event)
    }

    private func moveWindow(with event: NSEvent) {
        guard let grabPoint else { return }
        let point = event.locationInWindow
        setFrameOrigin(NSPoint(x: frame.origin.x + point.x - grabPoint.x,
                               y: frame.origin.y + point.y - grabPoint.y))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var dataDirectory: URL {
        // Smoke tests can use an isolated archive without touching the real history.
        if let path = ProcessInfo.processInfo.environment["FOLDERHOP_DATA_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolderHop", isDirectory: true)
    }

    private var state: AppState!
    private var tracker: FinderTracker!
    private var desktop: BoardWindow!
    private var settingsWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private var desktopLevel: NSWindow.Level {
        #if DEBUG
        // UI automation cannot send pointer events to desktop-level windows.
        // This development-only preview uses identical content at a normal level.
        if ProcessInfo.processInfo.arguments.contains("--folderhop-preview") { return .normal }
        #endif
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        state = AppState(dataDirectory: Self.dataDirectory)
        tracker = FinderTracker(state: state)
        state.setTracking = { [weak self] enabled in
            guard let self else { return }
            self.state.preferences.trackingEnabled = enabled
            if enabled && self.state.trackingStatus != .recording { self.tracker.start() }
        }
        state.preferencesChanged = { [weak self] old in self?.applyPreferences(previous: old) }
        state.folderOpened = { [weak self] path in self?.tracker.markOpened(path) }
        state.showSettings = { [weak self] in self?.presentSettings() }
        state.showDesktop = { [weak self] in self?.restoreDesktop() }
        state.moveHandleRegionChanged = { [weak self] region in self?.desktop?.moveHandleRegion = region }
        createDesktop()
        applyPreferences(previous: nil)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.clampDesktopToScreen() } }
        if !state.preferences.hasLaunched {
            state.preferences.hasLaunched = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
        desktop.saveFrame(usingName: "FolderHop.Desktop")
        state.save()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreDesktop()
        return true
    }

    private func createDesktop() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 388, height: min(528, visible.height - 60))
        desktop = BoardWindow(contentRect: NSRect(x: visible.maxX - size.width - 35,
                                                   y: visible.maxY - size.height - 30,
                                                   width: size.width, height: size.height),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        configureSurface(desktop)
        desktop.movingChanged = { [weak self] moving in self?.state.isMovingWindow = moving }
        desktop.hasShadow = false
        desktop.acceptsMouseMovedEvents = true
        desktop.title = "FolderHop 桌面小工具"
        desktop.level = desktopLevel
        desktop.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        desktop.contentMinSize = NSSize(width: 388, height: 468)
        desktop.contentMaxSize = NSSize(width: 600, height: 1_200)
        desktop.contentView = DesktopHostingView(rootView: FolderBoardView(state: state)
            .environment(\.locale, Locale(identifier: "zh_HK")))
        desktop.setFrameAutosaveName("FolderHop.Desktop")
        _ = desktop.setFrameUsingName("FolderHop.Desktop")
        if UserDefaults.standard.integer(forKey: "layoutRevision") < 4 {
            let oldFrame = desktop.frame
            desktop.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.maxY - 528,
                                     width: max(388, oldFrame.width), height: 528), display: false)
            UserDefaults.standard.set(4, forKey: "layoutRevision")
        }
        desktop.delegate = self
        clampDesktopToScreen()
    }

    private func configureSurface(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
    }

    private func applyPreferences(previous: FolderCore.AppPreferences?) {
        let prefs = state.preferences
        desktop.orderFrontRegardless()
        desktop.level = desktopLevel
        desktop.isMovable = !prefs.lockPosition
        if previous == nil || previous?.trackingEnabled != prefs.trackingEnabled {
            if prefs.trackingEnabled { tracker.start(requestConsent: previous != nil) }
            else { tracker.stop() }
        }
    }

    @objc private func presentSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 690),
                                   styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "FolderHop 設定"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(state: state)
                .environment(\.locale, Locale(identifier: "zh_HK")))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func restoreDesktop() {
        state.preferences.desktopVisible = true
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            desktop.setFrameOrigin(NSPoint(x: frame.maxX - desktop.frame.width - 30,
                                            y: frame.maxY - desktop.frame.height - 30))
        }
        clampDesktopToScreen()
        desktop.orderFrontRegardless()
        state.notify("小工具已放返桌面。顯示桌面就會見到。")
    }

    private func clampDesktopToScreen() {
        guard let desktop, !NSScreen.screens.isEmpty else { return }
        let screen = NSScreen.screens.max { a, b in
            area(desktop.frame.intersection(a.visibleFrame)) < area(desktop.frame.intersection(b.visibleFrame))
        }!
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = desktop.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        desktop.setFrame(frame, display: true)
    }

    private func area(_ rect: NSRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    private func installMainMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        appMenu.addItem(item("設定…", action: #selector(presentSettings)))
        let quit = item("結束 FolderHop", action: #selector(quit)); quit.keyEquivalent = "q"
        appMenu.addItem(quit)
        let editItem = NSMenuItem(title: "編輯", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "編輯")
        for (title, selector, key) in [
            ("復原", Selector(("undo:")), "z"), ("剪下", #selector(NSText.cut(_:)), "x"),
            ("複製", #selector(NSText.copy(_:)), "c"), ("貼上", #selector(NSText.paste(_:)), "v"),
            ("全選", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key)) }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }
}
