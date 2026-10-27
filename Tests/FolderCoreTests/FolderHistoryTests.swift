import XCTest
@testable import FolderCore

final class FolderHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFinderPermissionDenialAndVirtualLocationsAreDistinctFromTimeouts() {
        XCTAssertEqual(FinderFailureKind(errorCode: -1743), .permission)
        XCTAssertEqual(FinderFailureKind(errorCode: -1744), .permission)
        XCTAssertEqual(FinderFailureKind(errorCode: -1728), .noLocation)
        XCTAssertEqual(FinderFailureKind(errorCode: -1712), .temporary)
        XCTAssertEqual(FinderFailureKind(errorCode: -600), .temporary)
    }

    func testRecentDeduplicatesAndRevisitMovesToFront() {
        var history = FolderHistory()
        for (index, path) in ["/A", "/B", "/C", "/A"].enumerated() {
            history.recordVisit(path: path, at: now.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(history.recent(limit: 5).map(\.path), ["/A", "/C", "/B"])
        XCTAssertEqual(history.records.first { $0.path == "/A" }?.visits.count, 2)
    }

    func testFrequencyIsPrimaryEvenWhenLessRecent() {
        var history = FolderHistory()
        for _ in 0..<3 { history.recordVisit(path: "/Frequent", at: now.addingTimeInterval(-20 * 86_400)) }
        history.recordVisit(path: "/Recent", at: now)
        XCTAssertEqual(history.frequent(limit: 10, at: now).map(\.path), ["/Frequent", "/Recent"])
    }

    func testFrequencyTiesPreferMostRecent() {
        var history = FolderHistory()
        history.recordVisit(path: "/A", at: now.addingTimeInterval(-10))
        history.recordVisit(path: "/B", at: now)
        XCTAssertEqual(history.frequent(limit: 10, at: now).map(\.path), ["/B", "/A"])
    }

    func testThirtyDayBoundaryAndFutureEvents() {
        let history = FolderHistory(records: [
            .init(path: "/Old", lastVisit: now.addingTimeInterval(-FolderHistory.retention - 1), visits: [now.addingTimeInterval(-FolderHistory.retention - 1)]),
            .init(path: "/Boundary", lastVisit: now.addingTimeInterval(-FolderHistory.retention), visits: [now.addingTimeInterval(-FolderHistory.retention)]),
            .init(path: "/Future", lastVisit: now.addingTimeInterval(60), visits: [now.addingTimeInterval(60)])
        ])
        XCTAssertEqual(history.frequent(limit: 10, at: now).map(\.path), ["/Boundary"])
        XCTAssertEqual(history.recent(limit: 10).count, 3)
    }

    func testStationaryWindowAndDirectoryChanges() {
        var observer = NavigationObserver()
        XCTAssertEqual(observer.observe("/A/", windowID: "1"), "/A")
        for _ in 0..<100 { XCTAssertNil(observer.observe("/A", windowID: "1")) }
        XCTAssertEqual(observer.observe("/B", windowID: "1"), "/B")
        XCTAssertEqual(observer.observe("/A", windowID: "1"), "/A")
    }

    func testSwitchingWindowsIsAnActualVisit() {
        var observer = NavigationObserver()
        XCTAssertNotNil(observer.observe("/A", windowID: "1"))
        XCTAssertNotNil(observer.observe("/A", windowID: "2"))
        XCTAssertNil(observer.observe("/A", windowID: "2"))
    }

    func testClosingAllWindowsAllowsRevisit() {
        var observer = NavigationObserver()
        XCTAssertNotNil(observer.observe("/A"))
        XCTAssertNil(observer.observe(nil))
        XCTAssertNotNil(observer.observe("/A"))
    }

    func testOpeningFromAppIsNotDoubleCountedByFinder() {
        var observer = NavigationObserver()
        observer.markOpened("/A")
        XCTAssertNil(observer.observe("/A/", windowID: "new-window"))
        XCTAssertNil(observer.observe("/A", windowID: "new-window"))
        XCTAssertNotNil(observer.observe("/B", windowID: "new-window"))
    }

    func testPinningNeverCreatesVisitOrChangesFrequency() {
        var history = FolderHistory()
        history.setPinned(true, path: "/Pinned", at: now)
        XCTAssertEqual(history.pinned.count, 1)
        XCTAssertTrue(history.recent(limit: 5).isEmpty)
        XCTAssertTrue(history.frequent(limit: 10, at: now).isEmpty)
        history.setPinned(false, path: "/Pinned", at: now)
        XCTAssertTrue(history.records.isEmpty)
    }

    func testClearPreservesPinsAndExclusions() {
        var history = FolderHistory()
        history.recordVisit(path: "/A", at: now)
        history.setPinned(true, path: "/A", at: now)
        history.recordVisit(path: "/B", at: now)
        history.exclude(path: "/Private")
        history.clearVisits()
        XCTAssertEqual(history.pinned.map(\.path), ["/A"])
        XCTAssertTrue(history.recent(limit: 5).isEmpty)
        XCTAssertTrue(history.frequent(limit: 10, at: now).isEmpty)
        XCTAssertTrue(history.isExcluded("/Private"))
    }

    func testExclusionUsesPathBoundariesAndRemovesDescendants() {
        var history = FolderHistory()
        history.recordVisit(path: "/Private/Notes", at: now)
        history.recordVisit(path: "/PrivateOther", at: now)
        history.exclude(path: "/Private/")
        XCTAssertEqual(history.records.map(\.path), ["/PrivateOther"])
        XCTAssertFalse(history.recordVisit(path: "/Private/Sub", at: now))
        history.removeExclusion("/Private")
        XCTAssertTrue(history.recordVisit(path: "/Private/Sub", at: now))
    }

    func testPathValidationAndDistinctSameNames() {
        XCTAssertNil(FolderHistory.normalize("relative/path"))
        XCTAssertNil(FolderHistory.normalize("/A\0B"))
        var history = FolderHistory()
        history.recordVisit(path: "/Work/../Work/Notes/", at: now)
        history.recordVisit(path: "/Home/Notes", at: now)
        XCTAssertEqual(Set(history.records.map(\.path)), ["/Work/Notes", "/Home/Notes"])
        XCTAssertEqual(history.search("work notes").map(\.path), ["/Work/Notes"])
    }

    func testLimitsAndDefaultPreferences() {
        var history = FolderHistory()
        for number in 0..<25 { history.recordVisit(path: "/Folder\(number)", at: now.addingTimeInterval(-Double(number))) }
        XCTAssertEqual(history.recent(limit: 5).count, 5)
        XCTAssertEqual(history.frequent(limit: 10, at: now).count, 10)
        XCTAssertTrue(history.recent(limit: 0).isEmpty)
        XCTAssertTrue(history.frequent(limit: -1, at: now).isEmpty)
        XCTAssertEqual(AppPreferences().recentLimit, 5)
        XCTAssertEqual(AppPreferences().frequentLimit, 10)
        XCTAssertFalse(AppPreferences().trackingEnabled)
    }

    func testAllRealVisitsWithinWindowArePreserved() {
        var history = FolderHistory()
        for index in 0..<2_005 { history.recordVisit(path: "/Busy", at: now.addingTimeInterval(-Double(index))) }
        XCTAssertEqual(history.records.first?.visitCount(at: now), 2_005)
    }

    func testPersistenceRoundTripAndRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = ArchiveRepository(fileURL: directory.appendingPathComponent("history.json"))
        XCTAssertEqual(try repo.load(), SavedArchive())
        var archive = SavedArchive()
        archive.history.recordVisit(path: "/中文/Folder with spaces", at: now)
        archive.history.setPinned(true, path: "/中文/Folder with spaces", at: now)
        archive.preferences.frequentLimit = 15
        archive.preferences.hotkey.keyCode = 40
        try repo.save(archive)
        let restarted = ArchiveRepository(fileURL: repo.fileURL)
        XCTAssertEqual(try restarted.load(), archive)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: repo.fileURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptArchiveIsNeverSilentlyOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let broken = Data("broken json".utf8)
        try broken.write(to: url)
        let repo = ArchiveRepository(fileURL: url)
        XCTAssertThrowsError(try repo.load())
        let backup = try repo.preserveUnreadableArchive()
        XCTAssertEqual(try Data(contentsOf: backup), broken)
        XCTAssertEqual(try Data(contentsOf: url), broken)
        try repo.save(SavedArchive())
        XCTAssertEqual(try Data(contentsOf: backup), broken)
    }
}
