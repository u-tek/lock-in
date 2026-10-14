import Foundation

extension SessionEngine {
    /// Whole minutes focused in the sessions that ended within `interval` (from its start up to,
    /// not including, its end), solo and squad, from this phone's history. The weekly recap's
    /// "Last week: 6 h 20 m locked in" (M6). Like today's minutes, a session belongs to the moment
    /// it ended; the history keeps the last `SessionStore.historyLimit` sessions, far more than
    /// a week's.
    public func focusedMinutes(in interval: DateInterval) -> Int {
        let seconds = stored.history.reduce(0) { total, record in
            guard record.endedAt >= interval.start, record.endedAt < interval.end else { return total }
            return total + max(0, record.focusedSeconds)
        }
        return seconds / 60
    }
}
