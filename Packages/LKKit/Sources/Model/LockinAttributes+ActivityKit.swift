// The conformance sits apart from the type so the wire format compiles, and its tests run,
// wherever ActivityKit doesn't exist. Nothing else in Model touches ActivityKit.
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

extension LockinAttributes: ActivityAttributes {}
#endif
