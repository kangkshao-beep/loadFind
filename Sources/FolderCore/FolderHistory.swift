import Foundation

public struct FolderRecord: Codable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public var lastVisit: Date?
    public var visits: [Date]
    public var pinnedAt: Date?

    public init(path: String, lastVisit: Date? = nil, visits: [Date] = [], pinnedAt: Date? = nil) {
        self.path = path
        self.lastVisit = lastVisit
        self.visits = visits
        self.pinnedAt = pinnedAt
    }

    public var name: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }
    public var isPinned: Bool { pinnedAt != nil }

    public func visitCount(at now: Date) -> Int {
        visits.filter { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= FolderHistory.retention }.count
    }
}

public struct FolderHistory: Codable, Equatable {
    public static let retention: TimeInterval = 30 * 86_400
    public private(set) var records: [FolderRecord]
    public private(set) var excludedPaths: [String]

    public init(records: [FolderRecord] = [], excludedPaths: [String] = []) {
        self.records = records
        self.excludedPaths = excludedPaths
    }

    public static func normalize(_ raw: String) -> String? {
        guard raw.hasPrefix("/"), !raw.contains("\0") else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL.path
    }

    public func isExcluded(_ path: String) -> Bool {
        excludedPaths.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
    }

    @discardableResult
    public mutating func recordVisit(path raw: String, at now: Date) -> Bool {
        guard let path = Self.normalize(raw), !isExcluded(path) else { return false }
        if let index = records.firstIndex(where: { $0.path == path }) {
            records[index].lastVisit = now
            records[index].visits.append(now)
        } else {
            records.append(FolderRecord(path: path, lastVisit: now, visits: [now]))
        }
        prune(at: now)
        return true
    }

    public mutating func setPinned(_ pinned: Bool, path raw: String, at now: Date) {
        guard let path = Self.normalize(raw), !isExcluded(path) else { return }
        if let index = records.firstIndex(where: { $0.path == path }) {
            records[index].pinnedAt = pinned ? (records[index].pinnedAt ?? now) : nil
            if !pinned && records[index].lastVisit == nil { records.remove(at: index) }
        } else if pinned {
            records.append(FolderRecord(path: path, pinnedAt: now))
        }
    }

    public mutating func exclude(path raw: String) {
        guard let path = Self.normalize(raw) else { return }
        if !excludedPaths.contains(path) { excludedPaths.append(path) }
        let excluded = excludedPaths
        records.removeAll { record in excluded.contains { record.path == $0 || record.path.hasPrefix($0 == "/" ? "/" : $0 + "/") } }
    }

    public mutating func removeExclusion(_ path: String) {
        excludedPaths.removeAll { $0 == path }
    }

    public mutating func clearVisits() {
        records = records.filter(\.isPinned).map {
            FolderRecord(path: $0.path, pinnedAt: $0.pinnedAt)
        }
    }

    public mutating func prune(at now: Date) {
        for index in records.indices {
            records[index].visits = records[index].visits.filter {
                now.timeIntervalSince($0) <= Self.retention
            }
        }
        // Bound disk use without ever evicting a pinned folder.
        let unpinned = records.filter { !$0.isPinned }.sorted {
            ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast)
        }
        let retained = Set(unpinned.prefix(1_000).map(\.path))
        records.removeAll { !$0.isPinned && $0.visits.isEmpty && !retained.contains($0.path) }
    }

    public var pinned: [FolderRecord] {
        records.filter(\.isPinned).sorted {
            if $0.pinnedAt != $1.pinnedAt { return $0.pinnedAt! < $1.pinnedAt! }
            return $0.path < $1.path
        }
    }

    public func recent(limit: Int) -> [FolderRecord] {
        Array(records.filter { $0.lastVisit != nil }.sorted {
            if $0.lastVisit != $1.lastVisit { return $0.lastVisit! > $1.lastVisit! }
            return $0.path < $1.path
        }.prefix(max(0, limit)))
    }

    public func frequent(limit: Int, at now: Date) -> [FolderRecord] {
        // Frequency is primary. Recency breaks ties, keeping “most visited” literal.
        let counts = Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0.visitCount(at: now)) })
        return Array(records.filter { counts[$0.path, default: 0] > 0 }.sorted {
            let left = counts[$0.path, default: 0], right = counts[$1.path, default: 0]
            if left != right { return left > right }
            if $0.lastVisit != $1.lastVisit { return ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
            return $0.path < $1.path
        }.prefix(max(0, limit)))
    }

    public func search(_ query: String) -> [FolderRecord] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return recent(limit: 1_000) }
        return records.filter { record in
            terms.allSatisfy { record.path.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            let a = $0.name.localizedCaseInsensitiveContains(query)
            let b = $1.name.localizedCaseInsensitiveContains(query)
            if a != b { return a }
            if $0.lastVisit != $1.lastVisit { return ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
            return $0.path < $1.path
        }
    }
}

/// A stationary Finder window is a single visit, regardless of polling duration.
/// A → B → A is three visits; closing all windows resets the observation.
public struct NavigationObserver {
    private var lastPath: String?
    private var lastWindow: String?
    public init() {}

    public mutating func observe(_ raw: String?, windowID: String? = nil) -> String? {
        guard let raw, let path = FolderHistory.normalize(raw) else {
            lastPath = nil
            lastWindow = nil
            return nil
        }
        let changedWindow = lastWindow != nil && windowID != nil && lastWindow != windowID
        let changedPath = path != lastPath
        lastPath = path
        lastWindow = windowID
        guard changedPath || changedWindow else { return nil }
        return path
    }

    public mutating func markOpened(_ path: String) {
        lastPath = FolderHistory.normalize(path)
        lastWindow = nil
    }
}

public enum FinderFailureKind: Equatable {
    case permission, noLocation, temporary

    public init(errorCode: Int) {
        switch errorCode {
        case -1743, -1744: self = .permission
        case -1728: self = .noLocation
        default: self = .temporary
        }
    }
}
