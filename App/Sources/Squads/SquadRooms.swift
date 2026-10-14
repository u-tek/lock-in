import API
import Combine
import Foundation
import Model

/// How many people are locked in in each squad's open room: the "3 locked in" on Home's squad
/// picker.
///
/// A squad only says whether its room is open (`openSessionId`), so this asks the room itself
/// (`GET /sessions/:id`) for each open one. A handful of requests at most: free accounts have one
/// squad, Plus three. A room it can't read just shows as open, without a count.
@MainActor
final class SquadRooms: ObservableObject {
    /// People in the room who are still going (focusing, on a break or paused), by session id.
    @Published private(set) var lockedIn: [String: Int]

    private let api: (any LockinAPI)?

    init(api: any LockinAPI) {
        self.api = api
        lockedIn = [:]
    }

    private init(counts: [String: Int]) {
        api = nil
        lockedIn = counts
    }

    /// Fixed counts by session id, for snapshots and previews. Never touches the network.
    static func preview(_ counts: [String: Int] = [:]) -> SquadRooms {
        SquadRooms(counts: counts)
    }

    /// The count for a squad's open room, if it's open and could be read.
    func count(for squad: Squad) -> Int? {
        squad.openSessionId.flatMap { lockedIn[$0] }
    }

    /// Reads every open room in `squads`. Rooms that have closed drop out.
    func refresh(_ squads: [Squad]) async {
        guard let api, api.isConfigured else { return }
        var counts: [String: Int] = [:]
        for squad in squads {
            guard let sessionID = squad.openSessionId else { continue }
            do {
                let (_, state) = try await api.session(id: sessionID)
                if let state {
                    counts[sessionID] = state.m.filter(\.isActive).count
                }
            } catch {
                // Offline or the room just closed: the chip shows it open, without a count.
                continue
            }
        }
        if counts != lockedIn {
            lockedIn = counts
        }
    }
}
