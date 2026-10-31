import Foundation

/// Decides whether the overlay is showing, based on the last user activity.
public struct VisibilityPolicy: Sendable {
    public var idleTimeout: TimeInterval
    public var alwaysOn: Bool
    private var lastActivity: TimeInterval?

    public init(idleTimeout: TimeInterval = 5, alwaysOn: Bool = false) {
        self.idleTimeout = idleTimeout
        self.alwaysOn = alwaysOn
    }

    public mutating func recordActivity(at now: TimeInterval) {
        lastActivity = now
    }

    public func isVisible(at now: TimeInterval) -> Bool {
        if alwaysOn { return true }
        guard let hideTime else { return false }
        return now < hideTime
    }

    /// When the overlay should hide if no further activity occurs. `nil` means it never will.
    public var hideTime: TimeInterval? {
        guard !alwaysOn, let lastActivity else { return nil }
        return lastActivity + idleTimeout
    }
}
