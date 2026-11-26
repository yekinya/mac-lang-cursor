import CoreGraphics
import Testing
@testable import LangCursorCore

@Suite struct CatMotionTests {
    private let origin = CGPoint(x: 100, y: 100)
    private let tick = 1.0 / 120

    private func advance(_ cat: inout CatMotion, ticks: Int, target: CGPoint) {
        for _ in 0..<ticks { cat.update(deltaTime: tick, target: target) }
    }

    private func waitForRunning(_ cat: inout CatMotion, target: CGPoint) {
        for _ in 0..<1_200 {
            cat.update(deltaTime: tick, target: target)
            if cat.phase == .running { return }
        }
    }

    @Test func waitsOnePointEightRealSecondsThenStartsDirectionalRunImmediately() {
        var cat = CatMotion(position: origin)
        let target = CGPoint(x: -700, y: 100)
        cat.update(deltaTime: tick, target: target)
        advance(&cat, ticks: 215, target: target)
        #expect(cat.phase == .idle)
        #expect(cat.position == origin)
        cat.update(deltaTime: tick, target: target)
        #expect(cat.phase == .running)
        #expect(cat.pose.animation == .runRight)
        #expect(cat.pose.mirrored)
        #expect(cat.pose.frame == 0)
        #expect(cat.position == origin)
        cat.update(deltaTime: tick, target: target)
        #expect(cat.position.x < origin.x)
    }

    @Test(arguments: [0.4, 1.8, 3.5])
    func usesSelectedFollowDelay(_ seconds: Double) {
        var cat = CatMotion(position: origin)
        cat.followDelay = seconds
        let target = CGPoint(x: 500, y: 100)
        cat.update(deltaTime: tick, target: target)
        advance(&cat, ticks: Int((seconds / tick).rounded()) - 1, target: target)
        #expect(cat.phase == .idle)
        cat.update(deltaTime: tick, target: target)
        #expect(cat.phase == .running)
    }

    @Test func disablingIdleAnimationsKeepsTheRestingPoseStill() {
        var cat = CatMotion(position: origin)
        #expect(cat.idleAnimationsEnabled)
        cat.idleAnimationsEnabled = false
        let initial = cat.pose
        for _ in 0..<600 {
            cat.update(deltaTime: 0.1, target: origin)
            #expect(cat.pose == initial)
        }
    }

    @Test func meaningfulCursorMovementRestartsTheOnePointEightSecondDelay() {
        var cat = CatMotion(position: origin)
        let first = CGPoint(x: 700, y: 100)
        let second = CGPoint(x: 750, y: 150)
        cat.update(deltaTime: tick, target: first)
        advance(&cat, ticks: 120, target: first)
        cat.update(deltaTime: tick, target: second)
        advance(&cat, ticks: 215, target: second)
        #expect(cat.phase == .idle)
        #expect(cat.position == origin)
        cat.update(deltaTime: tick, target: second)
        #expect(cat.phase == .running)
    }

    @Test func subpixelJitterDoesNotRestartTheFollowDelay() {
        var cat = CatMotion(position: origin)
        let target = CGPoint(x: 700, y: 100)
        cat.update(deltaTime: tick, target: target)
        for index in 0..<215 {
            cat.update(deltaTime: tick, target: CGPoint(x: target.x + (index.isMultiple(of: 2) ? 0.5 : -0.5), y: target.y))
        }
        #expect(cat.phase == .idle)
        cat.update(deltaTime: tick, target: target)
        #expect(cat.phase == .running)
    }

    @Test func activeChaseKeepsItsPreviousTargetUntilNewCursorLocationHasRested() {
        var cat = CatMotion(position: origin)
        let first = CGPoint(x: -5_000, y: 100)
        let second = CGPoint(x: 5_000, y: 100)
        waitForRunning(&cat, target: first)
        advance(&cat, ticks: 240, target: first)
        var control = cat
        cat.update(deltaTime: tick, target: second)
        control.update(deltaTime: tick, target: first)
        for _ in 0..<215 {
            cat.update(deltaTime: tick, target: second)
            control.update(deltaTime: tick, target: first)
        }
        #expect(cat.position == control.position)
        #expect(cat.velocity == control.velocity)
        cat.update(deltaTime: tick, target: second)
        control.update(deltaTime: tick, target: first)
        #expect(cat.velocity.dx > control.velocity.dx)
    }

    @Test func distantCursorRunsAndSitsWithoutTeleporting() {
        var cat = CatMotion(position: origin)
        let target = CGPoint(x: 700, y: 100)
        var phases: Set<String> = []
        var previous = cat.position
        for _ in 0..<2_400 {
            cat.update(deltaTime: tick, target: target)
            phases.insert(String(describing: cat.phase))
            #expect(hypot(cat.position.x - previous.x, cat.position.y - previous.y) < 1.6)
            #expect(cat.position.x >= previous.x)
            #expect(cat.position.x <= target.x + 1.5)
            previous = cat.position
        }
        #expect(phases.isSuperset(of: ["running", "settling", "idle"]))
        #expect(hypot(cat.position.x - target.x, cat.position.y - target.y) < 0.01)
        #expect(cat.velocity == .zero)
    }

    @Test func slowMovementHasLongAccelerationAndDecelerationRamps() {
        var cat = CatMotion(position: origin)
        let far = CGPoint(x: 8_000, y: 100)
        waitForRunning(&cat, target: far)
        let start = cat.position
        advance(&cat, ticks: 24, target: far)
        #expect(cat.velocity.dx >= 17 && cat.velocity.dx <= 19)
        advance(&cat, ticks: 96, target: far)
        #expect(cat.velocity.dx >= 89 && cat.velocity.dx <= 91)
        advance(&cat, ticks: 120, target: far)
        #expect(abs(cat.velocity.dx - 126.5) < 0.01)
        #expect(cat.position.x - start.x > 120 && cat.position.x - start.x < 175)

        var arrival = CatMotion(position: origin)
        let near = CGPoint(x: 500, y: 100)
        waitForRunning(&arrival, target: near)
        var previousSpeed: CGFloat = 0
        var deceleratingTicks = 0
        for _ in 0..<1_800 {
            arrival.update(deltaTime: tick, target: near)
            let speed = hypot(arrival.velocity.dx, arrival.velocity.dy)
            if arrival.phase == .running && speed < previousSpeed - 0.0001 {
                deceleratingTicks += 1
                #expect(previousSpeed - speed <= 0.751)
            }
            previousSpeed = speed
            if arrival.phase == .idle { break }
        }
        #expect(deceleratingTicks > 60)
        #expect(arrival.phase == .idle)
        #expect(arrival.position == near)
    }

    @Test func idleAndSitAnimationPlaybackRunsAtHalfSpeed() {
        var idle = CatMotion(position: origin)
        advance(&idle, ticks: 72, target: origin)
        #expect(idle.pose.frame == 0)
        advance(&idle, ticks: 12, target: origin)
        #expect(idle.pose.frame == 1)

        var cat = CatMotion(position: origin)
        let target = CGPoint(x: 150, y: 100)
        for _ in 0..<1_800 {
            cat.update(deltaTime: tick, target: target)
            if cat.phase == .settling { break }
        }
        #expect(cat.phase == .settling)
        advance(&cat, ticks: 48, target: target)
        #expect(cat.phase == .settling)
        #expect(cat.pose.frame == 4)
        advance(&cat, ticks: 50, target: target)
        #expect(cat.phase == .idle)
    }

    @Test func runAnimationKeepsHalfSpeedCadenceDuringSlowTravel() {
        var cat = CatMotion(position: origin)
        let target = CGPoint(x: 8_000, y: 100)
        waitForRunning(&cat, target: target)
        advance(&cat, ticks: 240, target: target)
        #expect(abs(cat.velocity.dx - 126.5) < 0.01)
        let previousFrame = cat.pose.frame
        advance(&cat, ticks: 120, target: target)
        // At full cruise the former 26fps gait plays at13fps: one loop plus five frames.
        #expect((cat.pose.frame - previousFrame + 8) % 8 == 5)
    }

    @Test func cursorJitterDoesNotInterruptIdleOrGrooming() {
        var cat = CatMotion(position: origin, seed: 11)
        var visited: Set<Int> = []
        for index in 0..<10_800 {
            let jitter = CGFloat(index % 9 - 4)
            let pose = cat.update(deltaTime: tick, target: CGPoint(x: 100 + jitter, y: 100))
            visited.insert(pose.animation.rawValue)
            #expect(cat.position == origin)
            #expect(cat.phase != .running)
        }
        #expect(visited.isSuperset(of: [4, 5, 6, 7]))
    }

    @Test func everyFrameOfEveryIdleActivityIsReachable() {
        var cat = CatMotion(position: origin, seed: 22)
        var frames: [Int: Set<Int>] = [:]
        for _ in 0..<12_000 {
            let pose = cat.update(deltaTime: tick, target: origin)
            frames[pose.animation.rawValue, default: []].insert(pose.frame)
            #expect((0..<8).contains(pose.frame))
        }
        for row in 4...7 { #expect(frames[row] == Set(0..<8)) }
    }

    @Test func groomingStartsRunningDirectlyWhenDelayedTargetIsReleased() {
        for activity in [CatAnimation.lick, .wash, .stretch] {
            var baseline = CatMotion(position: origin, seed: 18)
            var releaseTick = 0
            for index in 0..<12_000 {
                baseline.update(deltaTime: tick, target: origin)
                if baseline.pose.animation == activity && baseline.pose.frame == 2 {
                    releaseTick = index + 9
                    break
                }
            }
            #expect(releaseTick > 217)
            var cat = CatMotion(position: origin, seed: 18)
            let target = CGPoint(x: -800, y: 100)
            for index in 0..<(releaseTick - 1) {
                cat.update(deltaTime: tick, target: index >= releaseTick - 217 ? target : origin)
            }
            #expect(cat.pose.animation == activity)
            #expect(cat.position == origin)
            cat.update(deltaTime: tick, target: target)
            #expect(cat.phase == .running)
            #expect(cat.pose.animation == .runRight)
            #expect(cat.pose.frame == 0)
            #expect(cat.pose.mirrored)
        }
    }

    @Test func leftFacingSitAndIdleKeepTheirMirroring() {
        var cat = CatMotion(position: origin)
        let target = CGPoint(x: -200, y: 100)
        waitForRunning(&cat, target: target)
        #expect(cat.pose.mirrored)
        var sawSit = false
        var sawIdle = false
        for _ in 0..<2_400 {
            cat.update(deltaTime: tick, target: target)
            if cat.phase == .settling {
                sawSit = true
                #expect(cat.pose.mirrored)
            }
            if sawSit && cat.phase == .idle {
                sawIdle = true
                #expect(cat.pose.mirrored)
                break
            }
        }
        #expect(sawSit && sawIdle)
    }

    @Test func verticalAndLeftMotionSelectCorrectAtlasRows() {
        for (target, animation, mirrored) in [
            (CGPoint(x: -500, y: 100), CatAnimation.runRight, true),
            (CGPoint(x: 100, y: 700), CatAnimation.runUp, false),
            (CGPoint(x: 100, y: -500), CatAnimation.runDown, false),
        ] {
            var cat = CatMotion(position: origin)
            waitForRunning(&cat, target: target)
            #expect(cat.pose.animation == animation)
            #expect(cat.pose.mirrored == mirrored)
        }
    }

    @Test func locomotionAndSitTransitionsVisitEveryAtlasFrame() {
        var frames: [Int: Set<Int>] = [:]
        for target in [CGPoint(x: 400, y: 100), CGPoint(x: 100, y: 400), CGPoint(x: 100, y: -200)] {
            var cat = CatMotion(position: origin)
            for _ in 0..<1_800 {
                let pose = cat.update(deltaTime: tick, target: target)
                frames[pose.animation.rawValue, default: []].insert(pose.frame)
            }
        }
        for row in 0...3 { #expect(frames[row] == Set(0..<8)) }
    }

    @Test func refreshRateDoesNotChangeTheChase() {
        var sixty = CatMotion(position: origin)
        var thirty = sixty
        let target = CGPoint(x: 1_500, y: 800)
        for _ in 0..<480 { sixty.update(deltaTime: 1.0 / 60, target: target) }
        for _ in 0..<240 { thirty.update(deltaTime: 1.0 / 30, target: target) }
        #expect(hypot(sixty.position.x - thirty.position.x, sixty.position.y - thirty.position.y) < 0.1)
        #expect(sixty.pose == thirty.pose)
    }

    @Test func suspensionAndInvalidInputCannotLaunchCatAcrossDesktop() {
        var cat = CatMotion(position: origin)
        let target = CGPoint(x: 8_000, y: 100)
        waitForRunning(&cat, target: target)
        advance(&cat, ticks: 240, target: target)
        let before = cat.position
        cat.update(deltaTime: 600, target: target)
        #expect(cat.position.x - before.x <= 12.66)
        let validPosition = cat.position
        cat.update(deltaTime: .nan, target: target)
        cat.update(deltaTime: 1, target: CGPoint(x: CGFloat.infinity, y: 0))
        #expect(cat.position == validPosition)
        cat.reset(position: CGPoint(x: -500, y: -200))
        #expect(cat.position == CGPoint(x: -500, y: -200))
        #expect(cat.velocity == .zero)
        #expect(cat.phase == .idle)
        advance(&cat, ticks: 216, target: target)
        #expect(cat.phase == .idle)
        cat.update(deltaTime: tick, target: target)
        #expect(cat.phase == .running)
    }

    @Test func directionChangesKeepSpeedAndPositionBounded() {
        var cat = CatMotion(position: origin)
        var sawLeft = false
        var sawRight = false
        for index in 0..<4_320 {
            let target = index % 1_440 < 720 ? CGPoint(x: -500, y: -200) : CGPoint(x: 700, y: 700)
            let before = cat.position
            cat.update(deltaTime: tick, target: target)
            #expect(hypot(cat.velocity.dx, cat.velocity.dy) <= 126.51)
            #expect(hypot(cat.position.x - before.x, cat.position.y - before.y) <= 1.6)
            #expect(cat.position.x.isFinite && cat.position.y.isFinite)
            sawLeft = sawLeft || cat.velocity.dx < -10
            sawRight = sawRight || cat.velocity.dx > 10
        }
        #expect(sawLeft && sawRight)
    }
}

@Suite struct CatPlacementTests {
    @Test func centerClampKeepsEntireSpriteInsideNegativeScreenCoordinates() {
        let screen = CGRect(x: -1_440, y: -900, width: 1_440, height: 900)
        let size = CGSize(width: 64, height: 64)
        for cursor in [CGPoint(x: -1_440, y: -900), CGPoint(x: 0, y: 0)] {
            let target = CatPlacement.target(cursor: cursor, screen: screen, catSize: size)
            let sprite = CGRect(x: target.x - 32, y: target.y - 32, width: 64, height: 64)
            #expect(screen.contains(sprite))
        }
    }

    @Test func tinyDesktopFallsBackToItsCenter() {
        let screen = CGRect(x: -10, y: -10, width: 20, height: 20)
        let target = CatPlacement.clamp(position: CGPoint(x: 900, y: 900), to: screen, catSize: CGSize(width: 64, height: 64))
        #expect(target == .zero)
    }
}
