import Foundation

public struct HotKeySpec: Codable, Equatable {
    public var keyCode: UInt32 = 49
    public var modifiers: UInt32 = 0x1800 // Carbon controlKey | optionKey
    public var keyName: String = "Space"
    public init() {}
    public var displayName: String {
        var result = ""
        if modifiers & 0x1000 != 0 { result += "⌃" }
        if modifiers & 0x0800 != 0 { result += "⌥" }
        if modifiers & 0x0200 != 0 { result += "⇧" }
        if modifiers & 0x0100 != 0 { result += "⌘" }
        return result + keyName
    }
}

public struct AppPreferences: Codable, Equatable {
    public var recentLimit = 5
    public var frequentLimit = 10
    public var trackingEnabled = false
    public var desktopVisible = true
    public var floatOnTop = false
    public var lockPosition = false
    public var hotkeyEnabled = true
    public var hotkey = HotKeySpec()
    public var hasLaunched = false
    public init() {}
}

public struct SavedArchive: Codable, Equatable {
    public var version = 1
    public var history: FolderHistory
    public var preferences: AppPreferences
    public init(history: FolderHistory = FolderHistory(), preferences: AppPreferences = AppPreferences()) {
        self.history = history
        self.preferences = preferences
    }
}

public struct ArchiveRepository {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> SavedArchive {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SavedArchive() }
        let data = try Data(contentsOf: fileURL)
        let archive = try JSONDecoder().decode(SavedArchive.self, from: data)
        guard archive.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        let paths = archive.history.records.map(\.path)
        guard Set(paths).count == paths.count,
              paths.allSatisfy({ FolderHistory.normalize($0) == $0 }) else { throw CocoaError(.coderReadCorrupt) }
        return archive
    }

    public func save(_ archive: SavedArchive) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Preserve unreadable data before starting a new archive. Never overwrite it.
    @discardableResult
    public func preserveUnreadableArchive() throws -> URL {
        let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        return backup
    }
}
