import Foundation

/// Hunger and litter timing for the desktop cat, independent of AppKit.
/// Each need has its own monotonic deadline. Zero disables it, and positive values select idle time.
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

    /// Stored preference for a fresh, independent interval between each pair of events.
    public static let randomDelay: TimeInterval = -1

    private struct Schedule: Sendable {
        let delay: TimeInterval
        var deadline: TimeInterval?

        init(delay: TimeInterval, now: TimeInterval) {
            self.delay = delay == CatNeeds.randomDelay ? delay : max(0, delay)
            restart(at: now)
        }

        mutating func restart(at now: TimeInterval) {
            switch delay {
            case CatNeeds.randomDelay: deadline = now + Double.random(in: 600...1200)
            case 0: deadline = nil
            default: deadline = now + delay
            }
        }

        mutating func cursorMoved(at now: TimeInterval) {
            if delay > 0 { deadline = now + delay }
        }

        func isDue(at now: TimeInterval) -> Bool {
            deadline.map { now >= $0 } ?? false
        }
    }

    public private(set) var errand: Errand = .none
    public var hungerDelay: TimeInterval { hunger.delay }
    public var poopDelay: TimeInterval { litter.delay }
    private var hunger: Schedule
    private var litter: Schedule
    private var mealStart: TimeInterval = 0

    public init(now: TimeInterval, hungerDelay: TimeInterval = 0, poopDelay: TimeInterval = 0) {
        hunger = Schedule(delay: hungerDelay, now: now)
        litter = Schedule(delay: poopDelay, now: now)
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
        hunger.cursorMoved(at: now)
        litter.cursorMoved(at: now)
        guard hunger.delay > 0, errand == .leaving else { return false }
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
        hunger.restart(at: now)
    }

    public mutating func restartTimers(at now: TimeInterval) {
        hunger.restart(at: now)
        litter.restart(at: now)
    }

    /// Advances the errand. `catArrived` means the cat is resting at the current errand target.
    public mutating func update(now: TimeInterval, catArrived: Bool) {
        switch errand {
        case .none where hunger.isDue(at: now):
            errand = .leaving
        case .leaving where catArrived:
            errand = .returning
        case .returning where catArrived:
            errand = .waiting
        case .eating where now - mealStart >= Self.eatingDuration:
            errand = .none
            // A full cat gets hungry again only after another full delay.
            hunger.restart(at: now)
        default:
            break
        }
    }

    /// Only an actual dropping consumes the deadline. A full screen or meal postpones it.
    public mutating func shouldPoop(now: TimeInterval, catResting: Bool, poopCount: Int) -> Bool {
        guard litter.isDue(at: now), catResting, errand == .none, poopCount < Self.maxPoops else { return false }
        if litter.delay == Self.randomDelay {
            litter.restart(at: now)
        } else {
            // Fixed idle modes re-arm on the next cursor movement.
            litter.deadline = nil
        }
        return true
    }

    public mutating func setHungerDelay(_ delay: TimeInterval, now: TimeInterval) {
        hunger = Schedule(delay: delay, now: now)
        errand = .none
    }

    public mutating func setPoopDelay(_ delay: TimeInterval, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        litter = Schedule(delay: delay, now: now)
    }
}
