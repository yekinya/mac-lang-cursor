import AppKit
import LangCursorCore

/// Owns a small, click-through floating window, independent of the language badge.
@MainActor
final class DesktopCatController {
    private(set) var isEnabled = true
    private(set) var size: CGFloat = 64 * 0.8

    private var species: PetSpecies = .cat
    private var clickReaction = true
    private var fliesEnabled = false
    private var poopLifetime: TimeInterval = 30
    var reactionText: (String) -> String = { $0 }

    private var motion = CatMotion(position: .zero)
    private var panel: DesktopCatPanel?
    private var spriteView: DesktopCatView?
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var previousTick: TimeInterval?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var started = false
    private var suspended = false
    private var needs = CatNeeds(now: ProcessInfo.processInfo.systemUptime)
    private var bowl: BowlPanel?
    /// Where the bowl was set down, and which way the cat faced it.
    private var bowlSpot: CGPoint?
    private var bowlMirrored = false
    private var poops: [PoopPanel] = []
    private var hissStart: TimeInterval?
    private var hissMirrored = false
    private var hissPanel: HissPanel?
    private var lastHissPhrase: Int?
    /// How long the swipe and shudder last after a click.
    private static let swipeDuration: TimeInterval = 0.6

    func start() {
        guard !started else { return }
        started = true
        suspended = false
        guard loadSprite(for: species) else {
            started = false
            return
        }
        observeEnvironment()
        monitorMouse()
        resetNearCursor()
        recreatePanel()
        scheduleTick(interval: 1 / 30)
    }

    private func loadSprite(for species: PetSpecies) -> Bool {
        do {
            let view = try DesktopCatView(atlas: DesktopCatAtlas(species: species), size: size)
            view.onClick = { [weak self] in self?.hiss() }
            spriteView = view
            return true
        } catch {
            NSLog("Could not load %@: %@", species.atlasName, String(describing: error))
            return false
        }
    }

    func setSpecies(_ newSpecies: PetSpecies) {
        guard species != newSpecies else { return }
        if started {
            guard loadSprite(for: newSpecies) else { return }
            clearReaction()
            recreatePanel()
        }
        species = newSpecies
    }

    func setFollowDelay(_ seconds: TimeInterval) { motion.followDelay = seconds }
    func setIdleAnimations(_ enabled: Bool) { motion.idleAnimationsEnabled = enabled }

    func setClickReaction(_ enabled: Bool) {
        clickReaction = enabled
        panel?.ignoresMouseEvents = !enabled
        if !enabled { clearReaction() }
    }

    private func clearReaction() {
        hissStart = nil
        hissPanel?.close()
        hissPanel = nil
    }

    func setPoopLifetime(_ seconds: TimeInterval) {
        poopLifetime = seconds
        for poop in poops { poop.setLifetime(seconds) }
    }

    func setFliesEnabled(_ enabled: Bool) {
        fliesEnabled = enabled
        if !enabled { for poop in poops { poop.removeFlies() } }
    }

    func stop() {
        started = false
        clearReaction()
        timer?.invalidate()
        timer = nil
        previousTick = nil
        panel?.close()
        panel = nil
        bowl?.close()
        bowl = nil
        for poop in poops { poop.close() }
        poops.removeAll()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        guard started else { return }
        if enabled {
            needs.restartTimers(at: ProcessInfo.processInfo.systemUptime)
            resetNearCursor()
            recreatePanel()
            for poop in poops { poop.orderFrontRegardless() }
            scheduleTick(interval: 1 / 30)
        } else {
            clearReaction()
            timer?.invalidate()
            timer = nil
            previousTick = nil
            panel?.orderOut(nil)
            needs.cancelErrand(at: ProcessInfo.processInfo.systemUptime)
            dismissBowl()
            for poop in poops { poop.orderOut(nil) }
        }
    }

    /// Seconds without cursor movement before the cat fetches its bowl. `0` turns it off.
    func setHungerDelay(_ seconds: TimeInterval) {
        needs.setHungerDelay(seconds, now: ProcessInfo.processInfo.systemUptime)
        dismissBowl()
    }

    /// Seconds the cursor must stay still before the cat poops. `0` turns it off.
    func setPoopDelay(_ seconds: TimeInterval) {
        needs.setPoopDelay(seconds)
    }

    func setSize(_ points: CGFloat) {
        size = min(max(points, 40), 96) * 0.8
        spriteView?.resize(to: size)
        panel?.setContentSize(NSSize(width: size, height: size))
        keepOnAvailableScreens()
        render()
    }

    private func resetNearCursor() {
        guard let screen = cursorScreen() else { return }
        motion.reset(position: CatPlacement.target(
            cursor: NSEvent.mouseLocation, screen: screen.visibleFrame,
            catSize: CGSize(width: size, height: size)
        ))
        previousTick = nil
    }

    private func cursorScreen() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
    }

    private func tick() {
        guard started, isEnabled, !suspended, let screen = cursorScreen() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = previousTick.map { min(max(now - $0, 0), 0.1) } ?? 0
        previousTick = now
        let target = errandTarget(on: screen)
        _ = motion.update(deltaTime: delta, target: target)
        let resting = motion.phase != .running && motion.phase != .settling
        // A target closer than the start distance never wakes the cat, so that counts as arrived.
        let arrived = resting && hypot(motion.position.x - target.x, motion.position.y - target.y) <= 20
        let before = needs.errand
        needs.update(now: now, catArrived: arrived)
        if before == .returning, needs.errand == .waiting {
            bowlSpot = motion.position
            bowlMirrored = motion.pose.mirrored
        }
        if before == .eating, needs.errand == .none { dismissBowl() }
        if needs.shouldPoop(now: now, catResting: resting, poopCount: poops.count) {
            dropPoop(on: screen)
        }
        keepOnAvailableScreens()
        render()

        // Resting needs few wakeups. Short sit clips keep all eight frames at 60 Hz.
        // Grooming runs at 30 Hz; cursor movement immediately restores a 60 Hz sample rate.
        switch motion.phase {
        case _ where hissStart != nil: scheduleTick(interval: 1 / 60)
        case _ where needs.errand == .eating: scheduleTick(interval: 1 / 30)
        case .idle: scheduleTick(interval: 1 / 12)
        case .licking, .washing, .stretching: scheduleTick(interval: 1 / 30)
        case .running, .settling: scheduleTick(interval: 1 / 60)
        }
    }

    /// While hungry, the cat first walks to the nearer side edge to pick up its bowl.
    private func errandTarget(on screen: NSScreen) -> CGPoint {
        let catSize = CGSize(width: size, height: size)
        let frame = screen.visibleFrame
        switch needs.errand {
        case .waiting, .eating:
            // Stay with the bowl even while the cursor moves over to serve food.
            if let bowlSpot { return bowlSpot }
        case .leaving:
            let edgeX = motion.position.x < frame.midX ? frame.minX : frame.maxX
            return CatPlacement.clamp(position: CGPoint(x: edgeX, y: motion.position.y),
                                      to: frame, catSize: catSize)
        case .none, .returning:
            break
        }
        return CatPlacement.target(cursor: NSEvent.mouseLocation, screen: frame, catSize: catSize)
    }

    private func dropPoop(on screen: NSScreen) {
        let poopSize = (size * 0.5).rounded() * 0.4
        // Behind the cat: a left-facing (mirrored) cat leaves it on its right.
        let behind: CGFloat = motion.pose.mirrored ? 1 : -1
        let spot = CatPlacement.clamp(
            position: CGPoint(x: motion.position.x + behind * size * 0.32,
                              y: motion.position.y - size * 0.32),
            to: screen.visibleFrame, catSize: CGSize(width: poopSize, height: poopSize)
        )
        let poop = PoopPanel(center: spot, size: poopSize, showsFlies: fliesEnabled)
        poop.onClean = { [weak self] poop in self?.clean(poop) }
        poops.append(poop)
        poop.appear()
        poop.setLifetime(poopLifetime)
        panel?.orderFrontRegardless()
        bowl?.orderFrontRegardless()
    }

    var poopCount: Int { poops.count }

    /// Clicked: turn toward the cursor, swipe with a paw, and hiss in some language.
    private func hiss() {
        guard clickReaction, isEnabled, !suspended else { return }
        hissStart = ProcessInfo.processInfo.systemUptime
        hissMirrored = NSEvent.mouseLocation.x < motion.position.x
        let index = CatHiss.nextIndex(after: lastHissPhrase)
        lastHissPhrase = index
        hissPanel?.close()
        let phrase: String
        switch species {
        case .cat: phrase = CatHiss.phrases[index].text
        case .dog: phrase = reactionText("멍!")
        case .hamster: phrase = reactionText("찍!")
        }
        let effect = HissPanel(catCenter: motion.position, catSize: size,
                               facingLeft: hissMirrored, text: phrase)
        hissPanel = effect
        effect.play { [weak self, weak effect] in
            effect?.close()
            if let self, hissPanel === effect { hissPanel = nil }
        }
        scheduleTick(interval: 1 / 60)
    }

    /// Clears every dropping at once (menu bar `똥 모두 치우기`).
    func cleanAllPoops() {
        for poop in poops { poop.fadeAway() }
        poops.removeAll()
    }

    private func clean(_ poop: PoopPanel) {
        guard let index = poops.firstIndex(where: { $0 === poop }) else { return }
        poops.remove(at: index)
        poop.fadeAway()
    }

    private func dismissBowl() {
        bowl?.dismiss()
        bowl = nil
        bowlSpot = nil
    }

    private func serveFood() {
        let carrying = needs.errand == .returning
        guard needs.serveFood(at: ProcessInfo.processInfo.systemUptime) else { return }
        if carrying {
            // Clicked on the way: put the bowl down right here and stop to eat.
            bowlMirrored = motion.pose.mirrored
            motion.reset(position: motion.position)
            bowlSpot = motion.position
        }
        renderBowl()
        bowl?.bounce()
        scheduleTick(interval: 1 / 30)
    }

    private func renderBowl() {
        guard needs.showsBowl, isEnabled, !suspended else { return }
        let bowlSize = (size * 0.55).rounded()
        if bowl == nil {
            let bowl = BowlPanel(size: bowlSize)
            bowl.onClick = { [weak self] in self?.serveFood() }
            self.bowl = bowl
            bowl.orderFrontRegardless()
        }
        guard let bowl else { return }
        bowl.food = needs.foodLeft(now: ProcessInfo.processInfo.systemUptime)
        bowl.acceptsFood = needs.bowlAcceptsFood
        // Carried at the mouth while walking; set down in front of the paws once it arrives.
        if needs.errand == .returning {
            let forward: CGFloat = motion.pose.mirrored ? -1 : 1
            bowl.move(center: CGPoint(x: motion.position.x + forward * size * 0.36,
                                      y: motion.position.y - size * 0.12))
        } else {
            let spot = bowlSpot ?? motion.position
            let forward: CGFloat = bowlMirrored ? -1 : 1
            bowl.move(center: CGPoint(x: spot.x + forward * size * 0.52, y: spot.y - size * 0.30))
        }
    }

    private func scheduleTick(interval: TimeInterval) {
        guard started, isEnabled, !suspended, spriteView != nil else { return }
        if timer != nil, abs(timerInterval - interval) < 0.0001 { return }
        timer?.invalidate()
        timerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval / 8
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func render() {
        guard let panel, let spriteView else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let start = hissStart, now - start >= Self.swipeDuration { hissStart = nil }
        var shake: CGFloat = 0
        if let start = hissStart {
            // Rapidly alternating stretch frames read as a paw swiping at the cursor,
            // with a shudder that dies down.
            let t = now - start
            let frame = Int(t * 14).isMultiple(of: 2) ? 3 : 7
            spriteView.render(CatPose(animation: .stretch, frame: frame, mirrored: hissMirrored))
            shake = sin(CGFloat(t) * 70) * size * 0.05 * CGFloat(1 - t / Self.swipeDuration)
        } else if needs.errand == .eating {
            // Head down at the bowl: the paw-licking row reads as eating, facing the bowl.
            let chewing = needs.eatingTime(now: now) * 5
            spriteView.render(CatPose(animation: .lick, frame: Int(chewing) % CatAnimation.frameCount,
                                      mirrored: bowlMirrored))
        } else {
            spriteView.render(motion.pose, wagTail: motion.idleAnimationsEnabled && motion.phase == .idle)
        }
        let origin = CGPoint(x: motion.position.x - size / 2 + shake, y: motion.position.y - size / 2)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        renderBowl()
    }

    private func recreatePanel() {
        guard let spriteView else { return }
        let old = panel
        let panel = DesktopCatPanel(size: size)
        panel.ignoresMouseEvents = !clickReaction
        panel.contentView = spriteView
        self.panel = panel
        old?.close()
        render()
        if isEnabled && !suspended {
            panel.orderFrontRegardless()
            bowl?.orderFrontRegardless()
        }
    }

    private func keepOnAvailableScreens() {
        let catSize = CGSize(width: size, height: size)
        guard !NSScreen.screens.contains(where: { $0.frame.contains(motion.position) }) else { return }
        guard let screen = cursorScreen() else { return }
        motion.reset(position: CatPlacement.clamp(
            position: motion.position, to: screen.visibleFrame, catSize: catSize
        ))
        previousTick = nil
    }

    private func monitorMouse() {
        let events: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.cursorMoved() }
            return event
        }
    }

    private func cursorMoved() {
        guard isEnabled, !suspended else { return }
        if needs.recordActivity(at: ProcessInfo.processInfo.systemUptime) { dismissBowl() }
        scheduleTick(interval: 1 / 60)
    }

    private func observeEnvironment() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspace) { controller in
            controller.recreatePanel()
        }
        observe(NSApplication.didChangeScreenParametersNotification, on: .default) { controller in
            controller.keepOnAvailableScreens()
            controller.recreatePanel()
        }
        for notification in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                             NSWorkspace.sessionDidResignActiveNotification] {
            observe(notification, on: workspace) { controller in controller.suspend() }
        }
        for notification in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                             NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(notification, on: workspace) { controller in controller.resume() }
        }
    }

    private func observe(
        _ name: Notification.Name, on center: NotificationCenter,
        perform action: @escaping @MainActor (DesktopCatController) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, observer))
    }

    private func suspend() {
        suspended = true
        timer?.invalidate()
        timer = nil
        previousTick = nil
        panel?.orderOut(nil)
        needs.cancelErrand(at: ProcessInfo.processInfo.systemUptime)
        dismissBowl()
        for poop in poops { poop.orderOut(nil) }
    }

    private func resume() {
        suspended = false
        previousTick = nil
        needs.restartTimers(at: ProcessInfo.processInfo.systemUptime)
        if isEnabled { for poop in poops { poop.orderFrontRegardless() } }
        keepOnAvailableScreens()
        recreatePanel()
        scheduleTick(interval: 1 / 30)
    }
}

@MainActor
private final class DesktopCatPanel: NSPanel {
    init(size: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        animationBehavior = .none
        // Above ordinary app windows. It takes clicks (to hiss) without activating the app.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
