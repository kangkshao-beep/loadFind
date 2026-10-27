import AppKit
import FolderCore
import Carbon

@MainActor
final class FinderTracker {
    private weak var state: AppState?
    private var timer: Timer?
    private var navigation = NavigationObserver()
    private var running = false
    private var permissionReady = false
    private var activationObserver: NSObjectProtocol?
    private var permissionTask: Task<Void, Never>?

    // NSAppleScript executes on the main thread. The short Apple Event timeout
    // bounds a hung Finder; polling only while Finder is frontmost avoids idle work.
    private let script = NSAppleScript(source: """
        with timeout of 1 second
            tell application "Finder"
                if (count of Finder windows) is 0 then return {}
                try
                    return {(id of front Finder window) as text, POSIX path of (target of front Finder window as alias)}
                on error number -1728
                    return {}
                end try
            end tell
        end timeout
        """)!

    init(state: AppState) {
        self.state = state
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activationChanged() }
        }
    }

    func start(requestConsent: Bool = true) {
        guard !running else { return }
        running = true
        state?.trackingStatus = .requesting
        // Consent may wait for a human. Keep that wait off the UI thread, outside
        // the short Finder query timeout. Starting at login never opens a new prompt.
        permissionTask = Task { [weak self] in
            let permission = await Task.detached(priority: .userInitiated) {
                let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
                return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), requestConsent)
            }.value
            guard !Task.isCancelled, let self, self.running else { return }
            if permission == noErr {
                self.permissionReady = true
                self.poll(force: true)
                self.activationChanged()
            } else {
                self.stop()
                self.state?.preferences.trackingEnabled = false
                self.state?.trackingStatus = FinderFailureKind(errorCode: Int(permission)) == .permission ? .denied : .unavailable
            }
        }
    }

    private func activationChanged() {
        timer?.invalidate()
        timer = nil
        guard running, permissionReady, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        poll()
        guard running else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.35
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        running = false
        permissionReady = false
        permissionTask?.cancel()
        permissionTask = nil
        timer?.invalidate()
        timer = nil
        state?.trackingStatus = .paused
    }

    func markOpened(_ path: String) { navigation.markOpened(path) }

    func poll(force: Bool = false) {
        guard running else { return }
        guard force || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        // Do not launch Finder again during shutdown or when it is not running.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty else { return }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            if FinderFailureKind(errorCode: number) == .permission {
                stop()
                state?.preferences.trackingEnabled = false
                state?.trackingStatus = .denied
            } else if FinderFailureKind(errorCode: number) != .noLocation {
                // Keep the timer for temporary Finder failures, without changing history.
                if state?.trackingStatus != .unavailable {
                    state?.notify("Finder 暫時未能回應（錯誤 \(number)）。請開啟一個 Finder 視窗再試。")
                }
                state?.trackingStatus = .unavailable
            }
            return
        }
        if state?.trackingStatus != .recording { state?.trackingStatus = .recording }
        // A permission/health query while another app is active is not a visit.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
        let windowID = result.numberOfItems == 2 ? result.atIndex(1)?.stringValue : nil
        let path = result.numberOfItems == 2 ? result.atIndex(2)?.stringValue : nil
        guard let observed = navigation.observe(path, windowID: windowID), let state,
              state.isDirectory(URL(fileURLWithPath: observed)) else { return }
        state.recordVisit(observed)
    }
}
