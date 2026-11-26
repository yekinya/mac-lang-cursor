import AppKit

/// A dropping left by the desktop cat. Unlike the cat, it takes clicks: one click cleans it up.
@MainActor
final class PoopPanel: NSPanel {
    var onClean: ((PoopPanel) -> Void)?
    private let flies: FliesPanel

    init(center: CGPoint, size: CGFloat) {
        flies = FliesPanel(poopCenter: center, poopSize: size)
        super.init(
            contentRect: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        // Just under the cat, so it walks over its own droppings.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        ignoresMouseEvents = false
        let view = PoopView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.onClick = { [weak self] in
            guard let self else { return }
            onClean?(self)
        }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Seconds the flies circle before zooming toward the viewer and vanishing.
    static let flyLifetime: TimeInterval = 5

    func appear() {
        alphaValue = 0
        flies.alphaValue = 0
        orderFrontRegardless()
        flies.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            animator().alphaValue = 1
            flies.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flyLifetime) { [weak self] in
            MainActor.assumeIsolated { self?.flies.flyAway() }
        }
    }

    /// Fades the dropping and its flies out, then closes both.
    func fadeAway() {
        ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
            flies.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        flies.orderFrontRegardless()
    }

    override func orderOut(_ sender: Any?) {
        flies.orderOut(sender)
        super.orderOut(sender)
    }

    override func close() {
        flies.close()
        super.close()
    }
}

/// A few flies wandering over a dropping. Animated by Core Animation, so they cost no app ticks.
@MainActor
private final class FliesPanel: NSPanel {
    private let fliesView: FliesView
    /// Once the flies have flown off, nothing brings this window back.
    private var finished = false

    init(poopCenter: CGPoint, poopSize: CGFloat) {
        // Roomy and click-through, so the flies can grow as they come toward the viewer.
        let side = poopSize * 6
        let frame = NSRect(x: 0, y: 0, width: side, height: side)
        fliesView = FliesView(frame: frame, poopSize: poopSize)
        super.init(
            contentRect: NSRect(x: poopCenter.x - side / 2, y: poopCenter.y + poopSize * 0.55 - side / 2,
                                width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        contentView = fliesView
    }

    override func orderFrontRegardless() {
        guard !finished else { return }
        super.orderFrontRegardless()
    }

    /// The flies swell as if flying at the screen, then disappear for good.
    func flyAway() {
        guard !finished else { return }
        // Above the cat and everything else on the desktop while they rush the viewer.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        if isVisible { super.orderFrontRegardless() }
        fliesView.zoomTowardViewer { [weak self] in
            guard let self else { return }
            finished = true
            orderOut(nil)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class FliesView: NSView {
    private var flies: [CALayer] = []
    private var swarmCenter = CGPoint.zero

    init(frame: NSRect, poopSize: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        swarmCenter = CGPoint(x: frame.width / 2, y: frame.height / 2 + poopSize * 0.09)
        let reach = CGSize(width: poopSize * 0.75, height: poopSize * 0.45)
        let baseSize = max(5, poopSize * 0.26)
        // Each dropping gets its own little swarm; every fly wanders its own way.
        for _ in 0..<Int.random(in: 2...3) {
            addFly(size: baseSize * CGFloat.random(in: 0.8...1.1), reach: reach)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    private func addFly(size: CGFloat, reach: CGSize) {
        let fly = CALayer()
        fly.bounds = CGRect(x: 0, y: 0, width: size, height: size)

        // Two pale wings that flutter, behind a dark body.
        let flutterSpeed = CFTimeInterval.random(in: 0.035...0.065)
        for side in [-1.0, 1.0] {
            let wing = CALayer()
            wing.bounds = CGRect(x: 0, y: 0, width: size * 0.5, height: size * 0.36)
            wing.position = CGPoint(x: size / 2 + CGFloat(side) * size * 0.2, y: size * 0.66)
            wing.cornerRadius = size * 0.18
            wing.backgroundColor = NSColor(calibratedWhite: 0.92, alpha: 0.85).cgColor
            let flutter = CABasicAnimation(keyPath: "opacity")
            flutter.fromValue = 1
            flutter.toValue = 0.25
            flutter.duration = flutterSpeed
            flutter.autoreverses = true
            flutter.repeatCount = .infinity
            flutter.timeOffset = .random(in: 0...flutterSpeed)
            wing.add(flutter, forKey: "flutter")
            fly.addSublayer(wing)
        }
        let body = CALayer()
        body.bounds = CGRect(x: 0, y: 0, width: size * 0.42, height: size * 0.36)
        body.position = CGPoint(x: size / 2, y: size * 0.42)
        body.cornerRadius = size * 0.18
        body.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        fly.addSublayer(body)

        // A closed, wandering loop through random spots over the dropping. Uneven key times make
        // the fly dart on some legs and hover on others, so no two flies (or laps) look alike.
        let stops = Int.random(in: 7...11)
        var points: [NSValue] = []
        for _ in 0..<stops {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let radius = CGFloat.random(in: 0.25...1)
            points.append(NSValue(point: CGPoint(x: swarmCenter.x + cos(angle) * reach.width * radius,
                                                 y: swarmCenter.y + sin(angle) * reach.height * radius
                                                    + reach.height * 0.3)))
        }
        points.append(points[0])
        var times: [Double] = [0]
        for _ in 1..<points.count { times.append(times.last! + .random(in: 0.4...1.6)) }
        let total = times.last!
        fly.position = points[0].pointValue

        let wander = CAKeyframeAnimation(keyPath: "position")
        wander.values = points
        wander.keyTimes = times.map { NSNumber(value: $0 / total) }
        wander.calculationMode = .cubic
        wander.duration = Double(stops) * .random(in: 0.22...0.4)
        wander.repeatCount = .infinity
        wander.timeOffset = .random(in: 0...wander.duration)
        fly.add(wander, forKey: "wander")

        layer?.addSublayer(fly)
        flies.append(fly)
    }

    /// Each fly leaves its path where it is and, at its own moment and pace, swells as if
    /// flying at the screen while veering off in its own direction, then vanishes.
    func zoomTowardViewer(completion: @escaping @MainActor () -> Void) {
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        let now = CACurrentMediaTime()
        for fly in flies {
            let current = fly.presentation()?.position ?? fly.position
            fly.removeAnimation(forKey: "wander")
            let outward = atan2(current.y - swarmCenter.y, current.x - swarmCenter.x)
            let heading = outward + CGFloat.random(in: -0.9...0.9)
            let distance = fly.bounds.width * CGFloat.random(in: 4...9)
            let away = CGPoint(x: current.x + cos(heading) * distance, y: current.y + sin(heading) * distance)
            let scale = CGFloat.random(in: 5...9)
            fly.position = away
            fly.transform = CATransform3DMakeScale(scale, scale, 1)
            fly.opacity = 0

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: current)
            move.toValue = NSValue(point: away)
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            grow.toValue = NSValue(caTransform3D: fly.transform)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            // Stay solid while approaching, then vanish at the very end.
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, NSNumber(value: Double.random(in: 0.55...0.75)), 1]
            let group = CAAnimationGroup()
            group.animations = [move, grow, fade]
            group.duration = .random(in: 0.7...1.2)
            // Staggered take-off; until then the fly hangs where it was.
            group.beginTime = now + .random(in: 0...0.5)
            group.fillMode = .backwards
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fly.add(group, forKey: "zoom")
        }
        CATransaction.commit()
    }
}

/// The faces a dropping can wear; each one picks at random.
private enum PoopFace: CaseIterable {
    case smile, wink, surprised, sleepy, grumpy, tongue, love, dizzy
}

@MainActor
private final class PoopView: NSView {
    var onClick: (() -> Void)?
    private let face = PoopFace.allCases.randomElement()!

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> NSRect {
            NSRect(x: w * x0, y: h * y0, width: w * (x1 - x0), height: h * (y1 - y0))
        }
        let fill = NSColor(calibratedRed: 0.56, green: 0.35, blue: 0.18, alpha: 1)
        let line = NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.09, alpha: 1)
        let lineWidth = max(1, w * 0.035)

        // Swirl from the tip down; each lower tier overlaps the one above it.
        let tip = NSBezierPath()
        tip.move(to: CGPoint(x: w * 0.40, y: h * 0.70))
        tip.curve(to: CGPoint(x: w * 0.60, y: h * 0.94),
                  controlPoint1: CGPoint(x: w * 0.42, y: h * 0.84), controlPoint2: CGPoint(x: w * 0.50, y: h * 0.90))
        tip.curve(to: CGPoint(x: w * 0.64, y: h * 0.70),
                  controlPoint1: CGPoint(x: w * 0.62, y: h * 0.86), controlPoint2: CGPoint(x: w * 0.68, y: h * 0.78))
        tip.close()
        let tiers = [tip,
                     NSBezierPath(ovalIn: rect(0.28, 0.52, 0.72, 0.78)),
                     NSBezierPath(roundedRect: rect(0.16, 0.30, 0.84, 0.62), xRadius: w * 0.16, yRadius: h * 0.15),
                     NSBezierPath(roundedRect: rect(0.06, 0.05, 0.94, 0.42), xRadius: w * 0.18, yRadius: h * 0.17)]
        for tier in tiers {
            fill.setFill()
            tier.fill()
            line.setStroke()
            tier.lineWidth = lineWidth
            tier.stroke()
        }
        // A glossy highlight on the top tier.
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: rect(0.34, 0.64, 0.46, 0.72)).fill()

        drawFace(w: w, h: h, lineWidth: lineWidth)
    }

    private func drawFace(w: CGFloat, h: CGFloat, lineWidth: CGFloat) {
        let left = CGPoint(x: w * 0.36, y: h * 0.29)
        let right = CGPoint(x: w * 0.64, y: h * 0.29)
        let r = w * 0.07
        let ink = NSColor(calibratedWhite: 0.08, alpha: 1)
        let pink = NSColor(calibratedRed: 1, green: 0.55, blue: 0.62, alpha: 1)

        func stroke(_ path: NSBezierPath, width: CGFloat = lineWidth) {
            ink.setStroke()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.stroke()
        }
        func openEye(_ c: CGPoint, scale: CGFloat = 1) {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r * scale, y: c.y - r * scale,
                                        width: r * 2 * scale, height: r * 2 * scale)).fill()
            ink.setFill()
            let p = r * 0.55 * scale
            NSBezierPath(ovalIn: NSRect(x: c.x - p, y: c.y - p * 1.2, width: p * 2, height: p * 2)).fill()
        }
        func arcEye(_ c: CGPoint, up: Bool) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: c.x - r, y: c.y))
            path.curve(to: CGPoint(x: c.x + r, y: c.y),
                       controlPoint1: CGPoint(x: c.x - r * 0.5, y: c.y + (up ? r : -r)),
                       controlPoint2: CGPoint(x: c.x + r * 0.5, y: c.y + (up ? r : -r)))
            stroke(path)
        }
        func mouth(from: CGFloat, to: CGFloat, y: CGFloat, bend: CGFloat) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: w * from, y: h * y))
            path.curve(to: CGPoint(x: w * to, y: h * y),
                       controlPoint1: CGPoint(x: w * (from + 0.04), y: h * (y + bend)),
                       controlPoint2: CGPoint(x: w * (to - 0.04), y: h * (y + bend)))
            stroke(path)
        }
        func cheeks() {
            pink.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: NSRect(x: w * 0.15, y: h * 0.17, width: w * 0.12, height: h * 0.07)).fill()
            NSBezierPath(ovalIn: NSRect(x: w * 0.73, y: h * 0.17, width: w * 0.12, height: h * 0.07)).fill()
        }
        func heart(_ c: CGPoint) {
            let s = r * 1.15
            let path = NSBezierPath()
            path.move(to: CGPoint(x: c.x, y: c.y - s))
            path.curve(to: CGPoint(x: c.x, y: c.y + s * 0.5),
                       controlPoint1: CGPoint(x: c.x - s * 1.6, y: c.y + s * 0.1),
                       controlPoint2: CGPoint(x: c.x - s * 0.6, y: c.y + s * 1.3))
            path.curve(to: CGPoint(x: c.x, y: c.y - s),
                       controlPoint1: CGPoint(x: c.x + s * 0.6, y: c.y + s * 1.3),
                       controlPoint2: CGPoint(x: c.x + s * 1.6, y: c.y + s * 0.1))
            NSColor(calibratedRed: 0.93, green: 0.15, blue: 0.25, alpha: 1).setFill()
            path.fill()
        }
        func crossEye(_ c: CGPoint) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: c.x - r * 0.8, y: c.y - r * 0.8))
            path.line(to: CGPoint(x: c.x + r * 0.8, y: c.y + r * 0.8))
            path.move(to: CGPoint(x: c.x - r * 0.8, y: c.y + r * 0.8))
            path.line(to: CGPoint(x: c.x + r * 0.8, y: c.y - r * 0.8))
            stroke(path)
        }

        switch face {
        case .smile:
            openEye(left); openEye(right); cheeks()
            mouth(from: 0.42, to: 0.58, y: 0.17, bend: -0.07)
        case .wink:
            openEye(left); arcEye(right, up: true); cheeks()
            mouth(from: 0.42, to: 0.58, y: 0.17, bend: -0.07)
        case .surprised:
            openEye(left, scale: 1.25); openEye(right, scale: 1.25)
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: w * 0.45, y: h * 0.09, width: w * 0.10, height: h * 0.10)).fill()
        case .sleepy:
            arcEye(left, up: false); arcEye(right, up: false)
            mouth(from: 0.46, to: 0.54, y: 0.15, bend: -0.03)
            let z = NSAttributedString(string: "z", attributes: [
                .font: NSFont.boldSystemFont(ofSize: h * 0.16), .foregroundColor: ink,
            ])
            z.draw(at: CGPoint(x: w * 0.74, y: h * 0.62))
        case .grumpy:
            openEye(left); openEye(right)
            let brows = NSBezierPath()
            brows.move(to: CGPoint(x: left.x - r * 1.1, y: left.y + r * 1.9))
            brows.line(to: CGPoint(x: left.x + r * 1.1, y: left.y + r * 1.2))
            brows.move(to: CGPoint(x: right.x + r * 1.1, y: right.y + r * 1.9))
            brows.line(to: CGPoint(x: right.x - r * 1.1, y: right.y + r * 1.2))
            stroke(brows)
            mouth(from: 0.42, to: 0.58, y: 0.13, bend: 0.06)
        case .tongue:
            arcEye(left, up: true); arcEye(right, up: true)
            pink.setFill()
            NSBezierPath(ovalIn: NSRect(x: w * 0.50, y: h * 0.07, width: w * 0.10, height: h * 0.10)).fill()
            mouth(from: 0.40, to: 0.60, y: 0.17, bend: -0.05)
        case .love:
            heart(left); heart(right); cheeks()
            mouth(from: 0.42, to: 0.58, y: 0.17, bend: -0.07)
        case .dizzy:
            crossEye(left); crossEye(right)
            let wave = NSBezierPath()
            wave.move(to: CGPoint(x: w * 0.40, y: h * 0.15))
            wave.curve(to: CGPoint(x: w * 0.60, y: h * 0.15),
                       controlPoint1: CGPoint(x: w * 0.46, y: h * 0.22), controlPoint2: CGPoint(x: w * 0.54, y: h * 0.08))
            stroke(wave)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// The food bowl the hungry cat carries in its mouth and sets down by the cursor.
@MainActor
final class BowlPanel: NSPanel {
    var onClick: (() -> Void)?
    private let bowlView: BowlView

    /// Remaining food from 0 (empty) to 1 (full).
    var food: Double = 0 {
        didSet { if bowlView.food != food { bowlView.food = food } }
    }

    /// Only an empty, set-down bowl takes a click; otherwise clicks pass through.
    var acceptsFood = false {
        didSet {
            ignoresMouseEvents = !acceptsFood
            bowlView.clickable = acceptsFood
        }
    }

    init(size: CGFloat) {
        bowlView = BowlView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        bowlView.onClick = { [weak self] in self?.onClick?() }
        // Layer-backed so the bowl can hop when food is served.
        bowlView.wantsLayer = true
        contentView = bowlView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func move(center: CGPoint) {
        let origin = CGPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2)
        if frame.origin != origin { setFrameOrigin(origin) }
    }

    /// A little hop when food lands in the bowl.
    func bounce() {
        guard let layer = contentView?.layer else { return }
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, frame.height * 0.22, 0, frame.height * 0.07, 0]
        hop.keyTimes = [0, 0.3, 0.6, 0.8, 1]
        hop.duration = 0.35
        layer.add(hop, forKey: "bounce")
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        })
    }
}

@MainActor
private final class BowlView: NSView {
    var onClick: (() -> Void)?
    var clickable = false
    var food: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        if clickable { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if clickable { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height

        // Kibble heaped above the rim, eaten from the top of the heap down.
        NSColor(calibratedRed: 0.55, green: 0.33, blue: 0.16, alpha: 1).setFill()
        let kibble: [(CGFloat, CGFloat)] = [(0.30, 0.50), (0.48, 0.52), (0.64, 0.50), (0.38, 0.56),
                                            (0.56, 0.57), (0.46, 0.61), (0.60, 0.63), (0.36, 0.62)]
        let pieces = Int((food * Double(kibble.count)).rounded(.up))
        for (x, y) in kibble.prefix(pieces) {
            NSBezierPath(ovalIn: NSRect(x: w * x - w * 0.07, y: h * y - h * 0.06,
                                        width: w * 0.14, height: h * 0.12)).fill()
        }

        // Bowl body: a wide top tapering to a flat foot.
        let body = NSBezierPath()
        body.move(to: CGPoint(x: w * 0.06, y: h * 0.48))
        body.line(to: CGPoint(x: w * 0.94, y: h * 0.48))
        body.curve(to: CGPoint(x: w * 0.74, y: h * 0.14),
                   controlPoint1: CGPoint(x: w * 0.92, y: h * 0.30),
                   controlPoint2: CGPoint(x: w * 0.84, y: h * 0.16))
        body.line(to: CGPoint(x: w * 0.26, y: h * 0.14))
        body.curve(to: CGPoint(x: w * 0.06, y: h * 0.48),
                   controlPoint1: CGPoint(x: w * 0.16, y: h * 0.16),
                   controlPoint2: CGPoint(x: w * 0.08, y: h * 0.30))
        body.close()
        NSColor(calibratedRed: 0.93, green: 0.36, blue: 0.40, alpha: 1).setFill()
        body.fill()
        NSColor(calibratedRed: 0.62, green: 0.18, blue: 0.22, alpha: 1).setStroke()
        body.lineWidth = max(1, w * 0.03)
        body.stroke()

        // Rim highlight.
        let rim = NSBezierPath(ovalIn: NSRect(x: w * 0.06, y: h * 0.42, width: w * 0.88, height: h * 0.12))
        NSColor(calibratedRed: 1, green: 0.62, blue: 0.64, alpha: 1).setFill()
        rim.fill()
        rim.stroke()

        // A small paw print on the side.
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: w * 0.44, y: h * 0.22, width: w * 0.12, height: h * 0.10)).fill()
        for x in [0.40, 0.48, 0.56] {
            NSBezierPath(ovalIn: NSRect(x: w * x, y: h * 0.33, width: w * 0.05, height: h * 0.05)).fill()
        }
    }
}

@MainActor
func configureFloating(_ panel: NSPanel) {
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isExcludedFromWindowsMenu = true
}
