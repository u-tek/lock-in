import Foundation
@testable import DeepFocus

/// A fresh, empty DeepFocus directory for one test.
func temporaryStorage() throws -> DeepFocusStorage {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DeepFocusTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return DeepFocusStorage(directory: directory)
}

func removeStorage(_ storage: DeepFocusStorage) {
    try? FileManager.default.removeItem(at: storage.directory)
}

/// 2027-01-15 08:00:00 UTC.
let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

func minutes(_ count: Double) -> TimeInterval {
    count * 60
}

/// Records what the engine asked of ManagedSettings.
final class FakeShields: DeepFocusShielding {
    enum Call: Equatable {
        /// Shielded, leaving out these tokens.
        case shield(except: [Data])
        case clear
    }

    var hasSelection = true
    private(set) var calls: [Call] = []

    var last: Call? {
        calls.last
    }

    func shield(except graces: [DeepFocusState.Grace]) {
        calls.append(.shield(except: graces.map(\.token)))
    }

    func clear() {
        calls.append(.clear)
    }
}

/// Records what the engine asked of DeviceActivity, and can refuse like it does.
final class FakeMonitor: DeepFocusMonitoring {
    struct Refusal: Error {}

    var refusesToStart = false
    private(set) var started: [(activity: DeepFocusActivity, schedule: DeepFocusSchedule)] = []
    private(set) var stopped: [[DeepFocusActivity]] = []

    func startMonitoring(_ activity: DeepFocusActivity, during schedule: DeepFocusSchedule) throws {
        if refusesToStart {
            throw Refusal()
        }
        started.append((activity, schedule))
    }

    func stopMonitoring(_ activities: [DeepFocusActivity]) {
        stopped.append(activities)
    }

    func starts(of activity: DeepFocusActivity) -> [DeepFocusSchedule] {
        started.filter { $0.activity == activity }.map(\.schedule)
    }

    func stops(of activity: DeepFocusActivity) -> Int {
        stopped.filter { $0.contains(activity) }.count
    }
}

/// An engine on fakes, in its own directory.
struct EngineFixture {
    let storage: DeepFocusStorage
    let shields = FakeShields()
    let monitor = FakeMonitor()
    let engine: DeepFocusEngine

    init() throws {
        storage = try temporaryStorage()
        engine = DeepFocusEngine(storage: storage, shields: shields, monitor: monitor)
    }

    var state: DeepFocusState {
        engine.currentState()
    }

    func tearDown() {
        removeStorage(storage)
    }
}

/// A token as the shield action extension would encode one; the fakes never decode it.
func token(_ name: String) -> Data {
    Data("{\"data\":\"\(name)\"}".utf8)
}
