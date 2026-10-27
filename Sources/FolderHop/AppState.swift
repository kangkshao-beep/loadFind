import AppKit
import Combine
import FolderCore
import ServiceManagement

enum TrackingStatus: Equatable {
    case paused, recording, requesting, denied, unavailable

    var label: String {
        switch self {
        case .paused: return "自動紀錄已暫停"
        case .recording: return "正在記低 Finder 到訪"
        case .requesting: return "等候 Finder 授權…"
        case .denied: return "需要 Finder 授權"
        case .unavailable: return "暫時連唔到 Finder"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var history: FolderHistory
    @Published var preferences: AppPreferences {
        didSet {
            guard preferences != oldValue else { return }
            save()
            preferencesChanged?(oldValue)
        }
    }
    @Published var trackingStatus: TrackingStatus = .paused
    @Published var message: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled

    var preferencesChanged: ((AppPreferences) -> Void)?
    var folderOpened: ((String) -> Void)?
    var showSettings: (() -> Void)?
    var showDesktop: (() -> Void)?
    var moveHandleRegionChanged: (([CGPoint]) -> Void)?
    var isMovingWindow = false
    var setTracking: ((Bool) -> Void)?

    private let repository: ArchiveRepository
    private var maySave = true
    private var messageTask: Task<Void, Never>?
    private var icons: [String: NSImage] = [:]
    private(set) var suppressCardClick = false
    private var cardPointerSequence = 0

    func cardPointerDown() {
        cardPointerSequence &+= 1
        suppressCardClick = false
    }
    func cardDragBegan() { suppressCardClick = true }
    func cardDragEnded() {
        // SwiftUI can deliver the Button action after the AppKit pan has ended.
        // Keep suppression through that mouse-up and its queued click action.
        let sequence = cardPointerSequence
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.cardPointerSequence == sequence else { return }
                self.suppressCardClick = false
            }
        }
    }

    func openFolderFromClick(_ folder: FolderRecord) {
        guard !suppressCardClick else { return }
        openFolder(folder)
    }

    init(dataDirectory: URL) {
        repository = ArchiveRepository(fileURL: dataDirectory.appendingPathComponent("history.json"))
        var loaded = SavedArchive()
        var initialMessage: String?
        do {
            loaded = try repository.load()
        } catch {
            do {
                _ = try repository.preserveUnreadableArchive()
                initialMessage = "舊紀錄讀唔到，已另存備份。你可以重新開始。"
            } catch {
                maySave = false
                initialMessage = "紀錄讀唔到，亦未能備份。暫時唔會覆寫原有檔案。"
            }
        }
        loaded.history.prune(at: Date())
        loaded.preferences.recentLimit = min(20, max(1, loaded.preferences.recentLimit))
        loaded.preferences.frequentLimit = min(20, max(1, loaded.preferences.frequentLimit))
        // “Temporarily on top” lasts for this session, never across relaunches.
        loaded.preferences.floatOnTop = false
        loaded.preferences.desktopVisible = true
        history = loaded.history
        preferences = loaded.preferences
        message = initialMessage
    }

    var recent: [FolderRecord] { visible(history.recent(limit: 1_000), limit: 5) }
    func visible(_ records: [FolderRecord], limit: Int = .max) -> [FolderRecord] {
        Array(records.lazy.filter { self.isDirectory(URL(fileURLWithPath: $0.path)) }.prefix(limit))
    }

    var starterFolders: [(name: String, symbol: String, url: URL)] {
        let fm = FileManager.default
        return [
            ("個人專屬", "house", fm.homeDirectoryForCurrentUser),
            ("文件", "doc.text", fm.urls(for: .documentDirectory, in: .userDomainMask).first!),
            ("下載項目", "arrow.down.circle", fm.urls(for: .downloadsDirectory, in: .userDomainMask).first!),
            ("桌面", "desktopcomputer", fm.urls(for: .desktopDirectory, in: .userDomainMask).first!)
        ].filter { isDirectory($0.2) && !history.isExcluded($0.2.path) }
    }

    func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    func recordVisit(_ path: String) {
        guard history.recordVisit(path: path, at: Date()) else { return }
        save()
    }

    func openFolder(_ record: FolderRecord) { openFolder(URL(fileURLWithPath: record.path)) }

    func openFolder(_ url: URL) {
        guard isDirectory(url) else {
            notify("搵唔到呢個資料夾，可能已搬走，或者外置磁碟未連接。")
            return
        }
        guard NSWorkspace.shared.open(url) else {
            notify("開唔到呢個資料夾，請檢查存取權限。")
            return
        }
        recordVisit(url.path)
        folderOpened?(url.path)
    }

    func togglePin(_ record: FolderRecord) {
        history.setPinned(!record.isPinned, path: record.path, at: Date())
        save()
    }

    @discardableResult
    func addFolders(_ urls: [URL]) -> Bool {
        let valid = urls.filter { isDirectory($0) && !history.isExcluded($0.path) }
        guard !valid.isEmpty else { notify("請揀資料夾；已忽略嘅位置要先喺設定取消忽略。"); return false }
        for url in valid { history.setPinned(true, path: url.path, at: Date()) }
        save()
        return true
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "釘選資料夾"
        panel.prompt = "釘選"
        panel.message = "揀你想一撳就到嘅地方。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { _ = addFolders(panel.urls) }
    }

    func exclude(_ record: FolderRecord) {
        history.exclude(path: record.path)
        save()
        notify("已忽略呢個資料夾同入面嘅子資料夾。可喺設定取消。")
    }

    func removeExclusion(_ path: String) {
        history.removeExclusion(path)
        save()
    }

    func copyPath(_ record: FolderRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.path, forType: .string)
        notify("已複製路徑")
    }

    func openTerminal(_ record: FolderRecord) {
        let url = URL(fileURLWithPath: record.path)
        guard isDirectory(url), let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            notify("開唔到終端機，請檢查資料夾係咪仲喺度。")
            return
        }
        // Pass the URL directly to Launch Services; paths are never shell commands.
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in
                if error != nil { self?.notify("終端機開唔到呢個位置。") }
            }
        }
    }

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        if icons.count > 256 { icons.removeAll() }
        icons[path] = image
        return image
    }

    func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            notify("未能更改登入設定。請先將 FolderHop 放入「應用程式」，再試一次。")
        }
    }

    func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "清除到訪紀錄？"
        alert.informativeText = "最近去過嘅清單會重新開始；忽略清單會保留。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清除紀錄")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            history.clearVisits()
            save()
            notify("到訪紀錄已清除")
        }
    }

    func notify(_ text: String) {
        messageTask?.cancel()
        message = text
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func save() {
        guard maySave else { return }
        do { try repository.save(SavedArchive(history: history, preferences: preferences)) }
        catch { message = "紀錄未能儲存，請檢查磁碟空間同資料夾權限。" }
    }
}
