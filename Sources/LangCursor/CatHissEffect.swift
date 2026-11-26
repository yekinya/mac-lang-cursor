import AppKit

/// The cat's angry reaction when clicked: three claw slashes in front of it and "hiss" in
/// some language shouted over its head. Click-through, plays once, then closes itself.
@MainActor
final class HissPanel: NSPanel {
    static let duration: CFTimeInterval = 1.6

    private let effectView: NSView
    private let catPoint: CGPoint
    private let catSize: CGFloat
    private let facingLeft: Bool
    private let text: String

    init(catCenter: CGPoint, catSize: CGFloat, facingLeft: Bool, text: String) {
        let width = catSize * 4.4
        let height = catSize * 3.2
        // The cat sits low in the middle; the shout gets the room above it.
        catPoint = CGPoint(x: width / 2, y: catSize * 1.0)
        self.catSize = catSize
        self.facingLeft = facingLeft
        self.text = text
        effectView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        super.init(
            contentRect: NSRect(x: catCenter.x - catPoint.x, y: catCenter.y - catPoint.y,
                                width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        configureFloating(self)
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = effectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func play(completion: @escaping @MainActor () -> Void) {
        guard let root = effectView.layer else { return }
        orderFrontRegardless()
        let scale = screen?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        addClawMarks(to: root)
        addShout(to: root, scale: scale)
        CATransaction.commit()
    }

    private func addClawMarks(to root: CALayer) {
        let forward: CGFloat = facingLeft ? -1 : 1
        let center = CGPoint(x: catPoint.x + forward * catSize * 0.62, y: catPoint.y + catSize * 0.05)
        let length = catSize * 0.6
        let gap = catSize * 0.15
        let now = CACurrentMediaTime()
        for index in 0..<3 {
            let offset = CGFloat(index - 1) * gap
            // Slashes run from upper-forward to lower-back, like a downward swipe of the paw.
            let start = CGPoint(x: center.x + forward * (length * 0.32 + offset), y: center.y + length / 2 - offset * 0.3)
            let end = CGPoint(x: center.x - forward * (length * 0.32 - offset), y: center.y - length / 2 - offset * 0.3)
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 + forward * catSize * 0.08,
                                                        y: (start.y + end.y) / 2))
            for (color, width) in [(NSColor.white.withAlphaComponent(0.9), catSize * 0.11),
                                   (NSColor(calibratedRed: 0.86, green: 0.1, blue: 0.16, alpha: 1), catSize * 0.055)] {
                let slash = CAShapeLayer()
                slash.path = path
                slash.fillColor = nil
                slash.strokeColor = color.cgColor
                slash.lineWidth = max(1.5, width)
                slash.lineCap = .round
                slash.opacity = 0

                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0
                draw.toValue = 1
                draw.duration = 0.12
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1, 1, 0]
                fade.keyTimes = [0, 0.55, 1]
                let group = CAAnimationGroup()
                group.animations = [draw, fade]
                group.duration = 0.75
                // One slash after another, as the paw sweeps across.
                group.beginTime = now + 0.08 + Double(index) * 0.05
                group.fillMode = .backwards
                slash.add(group, forKey: "slash")
                root.addSublayer(slash)
            }
        }
    }

    /// The hiss itself, as bare text over the cat's head (no bubble): it pops out, shudders,
    /// drifts up a little, and fades. A white outline keeps it readable on any background.
    private func addShout(to root: CALayer, scale: CGFloat) {
        let image = Self.outlinedText(text, size: max(12, catSize * 0.34))
        let forward: CGFloat = facingLeft ? -1 : 1
        let bounds = effectView.bounds
        let half = image.size.width / 2
        let x = min(max(catPoint.x + forward * catSize * 0.15, half + 2), bounds.width - half - 2)
        let shout = CALayer()
        shout.contents = image.layerContents(forContentsScale: scale)
        shout.contentsScale = scale
        shout.bounds = CGRect(origin: .zero, size: image.size)
        // Anchored at its bottom edge, so it pops up out of the cat's head.
        shout.anchorPoint = CGPoint(x: 0.5, y: 0)
        shout.position = CGPoint(x: x, y: catPoint.y + catSize * 0.4)

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.2, 1.25, 0.92, 1]
        pop.keyTimes = [0, 0.45, 0.75, 1]
        pop.duration = 0.28
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, 0.09, -0.09, 0.06, -0.06, 0]
        shake.beginTime = 0.28
        shake.duration = 0.35
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 0
        rise.toValue = catSize * 0.25
        rise.duration = Self.duration
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.75, 1]
        fade.duration = Self.duration
        let group = CAAnimationGroup()
        group.animations = [pop, shake, rise, fade]
        group.duration = Self.duration
        shout.opacity = 0
        shout.add(group, forKey: "shout")
        root.addSublayer(shout)
    }

    /// Bold red text with a thick white outline, rendered once into a bitmap.
    private static func outlinedText(_ text: String, size: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: size, weight: .black)
        let outline = size * 0.16
        let plain = NSAttributedString(string: text, attributes: [.font: font])
        let textSize = plain.size()
        let imageSize = NSSize(width: ceil(textSize.width + outline * 2), height: ceil(textSize.height + outline * 2))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        let origin = CGPoint(x: outline, y: outline)
        // Outline pass: a positive stroke width strokes only, so draw it first and fill on top.
        NSAttributedString(string: text, attributes: [
            .font: font, .strokeColor: NSColor.white, .strokeWidth: outline / size * 200,
        ]).draw(at: origin)
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(calibratedRed: 0.82, green: 0.08, blue: 0.13, alpha: 1),
            .strokeColor: NSColor(calibratedRed: 0.45, green: 0.02, blue: 0.05, alpha: 1), .strokeWidth: -2.5,
        ]).draw(at: origin)
        image.unlockFocus()
        return image
    }
}
