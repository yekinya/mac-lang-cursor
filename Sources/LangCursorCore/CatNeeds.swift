import Foundation

/// Hunger and litter timing for the desktop cat, independent of AppKit.
/// Times are monotonic seconds (`ProcessInfo.systemUptime`). A delay of `0` turns the need off.
public struct CatNeeds: Sendable {
    /// The meal errand that starts after the cursor has been still for `hungerDelay`.
    public enum Errand: Equatable, Sendable {
        /// Following the cursor as usual.
        case none
        /// Walking to the screen edge to pick up the bowl. Cursor movement calls this off.
        case leaving
        /// Carrying the empty bowl back. A click on it serves food right where the cat is.
        case returning
        /// Sitting beside the empty bowl until someone clicks it to serve food.
        case waiting
        /// Eating the served food.
        case eating
    }

    public static let maxPoops = 5
    public static let eatingDuration: TimeInterval = 6

    public private(set) var errand: Errand = .none
    public private(set) var hungerDelay: TimeInterval
    public private(set) var poopDelay: TimeInterval
    private var lastActivity: TimeInterval
    private var pooped = false
    private var mealStart: TimeInterval = 0

    public init(now: TimeInterval, hungerDelay: TimeInterval = 60, poopDelay: TimeInterval = 10) {
        self.hungerDelay = max(0, hungerDelay)
        self.poopDelay = max(0, poopDelay)
        lastActivity = now
    }

    /// The bowl is visible from the moment it is carried until the meal is finished.
    public var showsBowl: Bool { errand == .returning || errand == .waiting || errand == .eating }

    /// The empty bowl takes the serving click, whether it is still carried or already set down.
    public var bowlAcceptsFood: Bool { errand == .returning || errand == .waiting }

    /// Food remaining in the bowl, from 1 (just served) to 0 (empty).
    public func foodLeft(now: TimeInterval) -> Double {
        guard errand == .eating else { return 0 }
        return max(0, 1 - (now - mealStart) / Self.eatingDuration)
    }

    /// Seconds spent eating, for the chewing animation.
    public func eatingTime(now: TimeInterval) -> TimeInterval {
        errand == .eating ? max(0, now - mealStart) : 0
    }

    /// Cursor movement. Restarts the still-cursor countdowns and calls off a fetch that has
    /// not picked up the bowl yet. Returns `true` when it did. A cat already carrying or
    /// waiting with the bowl keeps going, because serving the food needs the cursor.
    @discardableResult
    public mutating func recordActivity(at now: TimeInterval) -> Bool {
        lastActivity = now
        pooped = false
        guard errand == .leaving else { return false }
        errand = .none
        return true
    }

    /// Serves food into the empty bowl. Returns `false` when there is no empty bowl to fill.
    @discardableResult
    public mutating func serveFood(at now: TimeInterval) -> Bool {
        guard bowlAcceptsFood else { return false }
        errand = .eating
        mealStart = now
        return true
    }

    /// Ends any errand at once, e.g. when the cat is hidden or the setting changes.
    public mutating func cancelErrand(at now: TimeInterval) {
        errand = .none
        lastActivity = now
    }

    /// Advances the errand. `catArrived` means the cat is resting at the current errand target.
    public mutating func update(now: TimeInterval, catArrived: Bool) {
        switch errand {
        case .none where hungerDelay > 0 && now - lastActivity >= hungerDelay:
            errand = .leaving
        case .leaving where catArrived:
            errand = .returning
        case .returning where catArrived:
            errand = .waiting
        case .eating where now - mealStart >= Self.eatingDuration:
            errand = .none
            // A full cat gets hungry again only after another full delay.
            lastActivity = now
        default:
            break
        }
    }

    /// `true` once per still period: after the cursor has been still for `poopDelay`, as soon as
    /// the cat is resting, free, and the screen has room. The next one needs the cursor to move.
    public mutating func shouldPoop(now: TimeInterval, catResting: Bool, poopCount: Int) -> Bool {
        guard poopDelay > 0, !pooped, now - lastActivity >= poopDelay,
              catResting, errand == .none, poopCount < Self.maxPoops else { return false }
        pooped = true
        return true
    }

    public mutating func setHungerDelay(_ delay: TimeInterval, now: TimeInterval) {
        hungerDelay = max(0, delay)
        // A new setting counts from now, so shortening it never fires instantly.
        cancelErrand(at: now)
    }

    public mutating func setPoopDelay(_ delay: TimeInterval) {
        poopDelay = max(0, delay)
    }
}
