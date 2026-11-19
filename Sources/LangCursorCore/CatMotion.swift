import CoreGraphics
import Foundation

/// Rows in the single, eight-column cat atlas. Left-facing motion mirrors `runRight`.
public enum CatAnimation: Int, CaseIterable, Sendable {
    case runRight = 0
    case runUp
    case runDown
    case sitDown
    case idle
    case lick
    case wash
    case stretch

    public static let frameCount = 8
}

public enum CatPhase: Sendable {
    case idle, running, settling, licking, washing, stretching
}

public struct CatPose: Equatable, Sendable {
    public let animation: CatAnimation
    public let frame: Int
    public let mirrored: Bool

    public init(animation: CatAnimation, frame: Int, mirrored: Bool) {
        self.animation = animation
        self.frame = frame
        self.mirrored = mirrored
    }

    public var isMoving: Bool {
        animation == .runRight || animation == .runUp || animation == .runDown
    }
}

/// Deterministic, display-independent cat behavior in AppKit's bottom-left coordinates.
/// `position` is the center of the sprite square. The caller supplies a screen-clamped target.
public struct CatMotion: Sendable {
    public private(set) var position: CGPoint
    public private(set) var velocity = CGVector.zero
    public private(set) var phase: CatPhase = .idle

    private var elapsed: TimeInterval = 0
    private var gait: Double = 0
    private var idleDeadline: TimeInterval = 5
    private var randomState: UInt64
    private var nextActivity = 0
    private var facing: CatAnimation = .runRight
    private var mirrored = false
    private var observedTarget: CGPoint
    private var followTarget: CGPoint
    private var targetQuietTime: TimeInterval = 0
    private var targetPending = false

    // The follow delay is wall-clock time; slowing animation must not turn it into six seconds.
    private static let followDelay: TimeInterval = 1.8
    private static let animationSpeed: Double = 0.5
    private static let movementSpeed: CGFloat = 1.15
    private static let settleDuration: TimeInterval = 0.4
    private static let startDistance: CGFloat = 18
    private static let arrivalDistance: CGFloat = 1.5
    // A long ramp into and out of the cruise speed gives the chase a soft ease-in/ease-out.
    private static let acceleration: CGFloat = 90
    private static let braking: CGFloat = 70

    public init(position: CGPoint, seed: UInt64 = 0xCA7_51A7) {
        self.position = Self.isFinite(position) ? position : .zero
        observedTarget = self.position
        followTarget = self.position
        randomState = seed
        idleDeadline = nextIdleDelay()
    }

    public var pose: CatPose {
        let animation: CatAnimation
        let frame: Int
        switch phase {
        case .idle:
            animation = .idle
            frame = Self.loopFrame(elapsed * 3)
        case .settling:
            animation = .sitDown
            frame = Self.transitionFrame(elapsed / Self.settleDuration)
        case .running:
            animation = facing
            frame = Self.loopFrame(gait)
        case .licking:
            animation = .lick
            frame = Self.loopFrame(elapsed * 8)
        case .washing:
            animation = .wash
            frame = Self.loopFrame(elapsed * 8)
        case .stretching:
            animation = .stretch
            frame = Self.transitionFrame(elapsed / (8.0 / 9.0))
        }
        // Keep the last horizontal direction through sitting and idle, including the tail.
        // Resetting mirroring here would turn a left-running cat right before it sits.
        return CatPose(animation: animation, frame: frame,
                       mirrored: animation != .runUp && animation != .runDown && mirrored)
    }

    /// A suspended app advances at most a tenth of a second on its first resumed tick.
    /// Small integration steps keep acceleration and arrival consistent at different refresh rates.
    @discardableResult
    public mutating func update(deltaTime: TimeInterval, target: CGPoint) -> CatPose {
        guard deltaTime.isFinite, deltaTime > 0, Self.isFinite(target) else { return pose }
        var remaining = min(deltaTime, 0.1)
        while remaining > 0.000_001 {
            let step = min(remaining, 1.0 / 120.0)
            advance(step, target: target)
            remaining -= step
        }
        return pose
    }

    /// Used after a display disappears or when the companion is enabled again.
    public mutating func reset(position: CGPoint) {
        guard Self.isFinite(position) else { return }
        self.position = position
        velocity = .zero
        elapsed = 0
        gait = 0
        phase = .idle
        observedTarget = position
        followTarget = position
        targetQuietTime = 0
        targetPending = false
        idleDeadline = nextIdleDelay()
    }

    private mutating func advance(_ dt: TimeInterval, target: CGPoint) {
        updateFollowTarget(target, deltaTime: dt)
        let difference = CGVector(dx: followTarget.x - position.x, dy: followTarget.y - position.y)
        let distance = Self.length(difference)
        elapsed += dt * Self.animationSpeed

        switch phase {
        case .idle, .licking, .washing, .stretching:
            // A separate start threshold prevents tiny cursor movements from repeatedly waking it.
            if distance > Self.startDistance {
                startRunning(toward: difference)
                return
            }
            advanceRestingActivity()
        case .settling:
            if distance > Self.startDistance {
                startRunning(toward: difference)
            } else if elapsed >= Self.settleDuration {
                enterIdle()
            }
        case .running:
            move(dt, difference: difference, distance: distance)
        }
    }

    private mutating func updateFollowTarget(_ target: CGPoint, deltaTime: TimeInterval) {
        if hypot(target.x - observedTarget.x, target.y - observedTarget.y) > 2 {
            observedTarget = target
            targetQuietTime = 0
            targetPending = true
        } else if targetPending {
            targetQuietTime += deltaTime
            if targetQuietTime + 0.000_001 >= Self.followDelay {
                followTarget = observedTarget
                targetPending = false
            }
        }
    }

    private mutating func move(_ dt: TimeInterval, difference: CGVector, distance: CGFloat) {
        let oldSpeed = Self.length(velocity)
        if distance <= Self.arrivalDistance && oldSpeed < 30 {
            position.x += difference.dx
            position.y += difference.dy
            velocity = .zero
            enter(.settling)
            return
        }

        let cruise = min(CGFloat(110), 72 + distance * 0.03) * Self.movementSpeed
        let desiredSpeed = min(cruise, sqrt(2 * Self.braking * distance), distance * 9)
        let inverseDistance = distance > 0.0001 ? 1 / distance : 0
        let desired = CGVector(
            dx: difference.dx * inverseDistance * desiredSpeed,
            dy: difference.dy * inverseDistance * desiredSpeed
        )
        let change = CGVector(dx: desired.dx - velocity.dx, dy: desired.dy - velocity.dy)
        let changeLength = Self.length(change)
        let limit = Self.acceleration * CGFloat(dt)
        let scale = changeLength > limit ? limit / changeLength : 1
        velocity.dx += change.dx * scale
        velocity.dy += change.dy * scale

        let displacement = CGVector(dx: velocity.dx * CGFloat(dt), dy: velocity.dy * CGFloat(dt))
        position.x += displacement.dx
        position.y += displacement.dy
        let speed = Self.length(velocity)
        updateFacing(direction: velocity, speed: speed)
        // Keep the original 7–26fps range before the requested half-speed playback.
        // Slower travel has its own scale so it does not halve the animation a second time.
        gait += max(7, min(26, Double(speed) / (110 * Self.movementSpeed) * 26)) * dt * Self.animationSpeed
    }

    private mutating func startRunning(toward direction: CGVector) {
        enter(.running)
        gait = 0
        updateFacing(direction: direction, speed: Self.length(direction))
    }

    private mutating func updateFacing(direction: CGVector, speed: CGFloat) {
        guard speed > 12 else { return }
        let horizontal = abs(direction.dx)
        let vertical = abs(direction.dy)
        // Hysteresis around diagonal headings avoids alternating atlas rows every frame.
        let verticalThreshold: CGFloat = facing == .runRight ? 1.35 : 0.85
        if vertical > horizontal * verticalThreshold {
            facing = direction.dy > 0 ? .runUp : .runDown
        } else {
            facing = .runRight
            mirrored = direction.dx < 0
        }
    }

    private mutating func advanceRestingActivity() {
        switch phase {
        case .idle where elapsed >= idleDeadline:
            let activities: [CatPhase] = [.licking, .washing, .stretching]
            enter(activities[nextActivity])
            nextActivity = (nextActivity + 1) % activities.count
        case .licking where elapsed >= 2, .washing where elapsed >= 2:
            enterIdle()
        case .stretching where elapsed >= 8.0 / 9.0:
            enterIdle()
        default:
            break
        }
    }

    private mutating func enter(_ phase: CatPhase) {
        self.phase = phase
        elapsed = 0
    }

    private mutating func enterIdle() {
        enter(.idle)
        idleDeadline = nextIdleDelay()
    }

    private mutating func nextIdleDelay() -> TimeInterval {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return 4 + Double(randomState >> 32) / Double(UInt32.max) * 4
    }

    private static func length(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func loopFrame(_ phase: Double) -> Int {
        Int(phase) % CatAnimation.frameCount
    }

    private static func transitionFrame(_ progress: Double) -> Int {
        min(7, max(0, Int(progress * 8)))
    }
}
