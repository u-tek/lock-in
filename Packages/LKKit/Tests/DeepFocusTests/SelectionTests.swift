import FamilyControls
import Foundation
import Testing
@testable import DeepFocus

// The picker's tokens are opaque and only the system makes them, so these tests round-trip an
// empty selection and check the file handling around it; nothing here asks FamilyControls for
// anything.

@Suite struct SelectionTests {
    @Test func nothingSavedLoadsEmpty() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let selection = DeepFocusSelection(storage: storage)
        #expect(selection.load() == FamilyActivitySelection())
        #expect(selection.summary.isEmpty)
    }

    @Test func roundTripsThroughTheAppGroupFile() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let selection = DeepFocusSelection(storage: storage)
        try selection.save(FamilyActivitySelection())
        #expect(FileManager.default.fileExists(atPath: storage.selectionURL.path))
        // A second instance, as another process would make, reads the same thing.
        #expect(DeepFocusSelection(storage: storage).load() == FamilyActivitySelection())
    }

    @Test func savingCreatesTheDirectory() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let nested = DeepFocusStorage(directory: storage.directory.appendingPathComponent("DeepFocus", isDirectory: true))
        try DeepFocusSelection(storage: nested).save(FamilyActivitySelection())
        #expect(FileManager.default.fileExists(atPath: nested.selectionURL.path))
    }

    @Test func anUnreadableFileLoadsEmpty() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        try Data("not a selection".utf8).write(to: storage.selectionURL)
        #expect(DeepFocusSelection(storage: storage).load() == FamilyActivitySelection())
    }

    @Test func clearForgetsTheChoice() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let selection = DeepFocusSelection(storage: storage)
        try selection.save(FamilyActivitySelection())
        selection.clear()
        #expect(!FileManager.default.fileExists(atPath: storage.selectionURL.path))
        selection.clear()
    }

    @Test func summaryCounts() {
        let some = DeepFocusSelection.Summary(applications: 3, categories: 1, webDomains: 2)
        #expect(!some.isEmpty)
        #expect(some.total == 6)
        #expect(!some.isOverLimit)
        #expect(DeepFocusSelection.Summary(applications: 0, categories: 0, webDomains: 0).isEmpty)
        #expect(DeepFocusSelection.Summary(FamilyActivitySelection()) == .init(applications: 0, categories: 0, webDomains: 0))
    }

    @Test func overFiftyOfAnythingIsOverTheLimit() {
        #expect(DeepFocusSelection.Summary.limit == 50)
        #expect(!DeepFocusSelection.Summary(applications: 50, categories: 50, webDomains: 50).isOverLimit)
        #expect(DeepFocusSelection.Summary(applications: 51, categories: 0, webDomains: 0).isOverLimit)
        #expect(DeepFocusSelection.Summary(applications: 0, categories: 51, webDomains: 0).isOverLimit)
        #expect(DeepFocusSelection.Summary(applications: 0, categories: 0, webDomains: 51).isOverLimit)
    }
}

@Suite struct SharedFileTests {
    private struct Sample: Codable, Equatable {
        var name: String
        var at: Double
    }

    @Test func writesWholeFilesAndReadsThemBack() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let url = storage.directory.appendingPathComponent("sample.json")
        #expect(SharedFile.read(Sample.self, from: url) == nil)
        try SharedFile.write(Sample(name: "one", at: 1.5), to: url)
        try SharedFile.write(Sample(name: "two", at: 2.25), to: url)
        #expect(SharedFile.read(Sample.self, from: url) == Sample(name: "two", at: 2.25))
        // Nothing left over from the atomic replace.
        let files = try FileManager.default.contentsOfDirectory(atPath: storage.directory.path)
        #expect(files == ["sample.json"])
    }

    @Test func lockFilesAreCreatedAndReusable() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let url = storage.stateLockURL
        let first = try SharedFile.withLock(url) { _ in 1 }
        let second = try SharedFile.withLock(url) { _ in 2 }
        #expect(first + second == 3)
    }

    @Test func aHeldLockMakesOthersWait() throws {
        let storage = try temporaryStorage()
        defer { removeStorage(storage) }
        let url = storage.stateLockURL
        let started = Date()
        let waited = try SharedFile.withLock(url) { _ -> TimeInterval in
            // A second opening of the same file can't take the lock while this one holds it, so
            // it waits out its (short) timeout and goes ahead.
            let inner = Date()
            try SharedFile.withLock(url, timeout: 0.2) { _ in }
            return Date().timeIntervalSince(inner)
        }
        #expect(waited >= 0.2)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}
