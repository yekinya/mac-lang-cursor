import AppKit
import ImageIO
import LangCursorCore
import QuartzCore

/// A single GPU texture for every animation. Frames are never decoded or cropped on a tick.
@MainActor
final class DesktopCatAtlas {
    static let columns = 8
    static let rows = 8

    let species: PetSpecies
    let image: CGImage

    init(species: PetSpecies) throws {
        guard let url = Bundle.module.url(forResource: species.atlasName, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              image.width.isMultiple(of: Self.columns),
              image.height.isMultiple(of: Self.rows),
              image.width / Self.columns == image.height / Self.rows else {
            throw AtlasError.invalidResource
        }
        self.species = species
        self.image = image
    }

    func contentsRect(for pose: CatPose) -> CGRect {
        CGRect(
            x: CGFloat(pose.frame) / CGFloat(Self.columns),
            // macOS CALayer contents coordinates begin at the image's bottom edge.
            // The atlas manifest numbers rows from the top.
            y: CGFloat(Self.rows - 1 - pose.animation.rawValue) / CGFloat(Self.rows),
            width: 1 / CGFloat(Self.columns),
            height: 1 / CGFloat(Self.rows)
        )
    }

    enum AtlasError: Error {
        case invalidResource
    }
}

@MainActor
final class DesktopCatView: NSView {
    /// Clicking the cat makes it hiss and swipe.
    var onClick: (() -> Void)?

    private let facing = CALayer()
    private let sprite = CALayer()
    private let dogTail: DogTail?
    private let atlas: DesktopCatAtlas
    private var renderedPose: CatPose?

    init(atlas: DesktopCatAtlas, size: CGFloat) {
        self.atlas = atlas
        dogTail = atlas.species == .dog ? DogTail(image: atlas.image) : nil
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        sprite.contents = atlas.image
        sprite.contentsGravity = .resize
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.isOpaque = false
        layer?.addSublayer(facing)
        if let dogTail { facing.addSublayer(dogTail.layer) }
        facing.addSublayer(sprite)
        resize(to: size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func resize(to size: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame.size = NSSize(width: size, height: size)
        facing.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        facing.position = CGPoint(x: size / 2, y: size / 2)
        sprite.frame = facing.bounds
        dogTail?.resize(to: size)
        CATransaction.commit()
    }

    func render(_ pose: CatPose, wagTail: Bool = false) {
        let wagging = wagTail && pose.animation == .idle && dogTail != nil
        guard pose != renderedPose || wagging != (sprite.mask != nil) else { return }
        renderedPose = pose
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cell = atlas.contentsRect(for: pose)
        sprite.contentsRect = cell
        facing.setAffineTransform(CGAffineTransform(scaleX: pose.mirrored ? -1 : 1, y: 1))
        if let dogTail {
            sprite.mask = wagging ? dogTail.bodyMask : nil
            dogTail.update(cell: cell, wagging: wagging)
        }
        CATransaction.commit()
    }
}

/// The same tail tip occupies this region of all eight seated puppy frames.
/// Swing it behind the body around the rump while the original blink loop plays.
@MainActor
private final class DogTail {
    let layer = CALayer()
    let bodyMask = CAShapeLayer()
    // Coordinates within a 128px packed frame, measured from the bottom left.
    private let tail = CGRect(x: 18, y: 16, width: 23, height: 24)
    private let hinge = CGPoint(x: 41, y: 25)
    private let cellSize: CGFloat = 128

    init(image: CGImage) {
        layer.contents = image
        layer.isHidden = true
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.anchorPoint = CGPoint(x: (hinge.x - tail.minX) / tail.width,
                                    y: (hinge.y - tail.minY) / tail.height)
        bodyMask.fillRule = .evenOdd
    }

    func resize(to size: CGFloat) {
        let scale = size / cellSize
        let rect = tail.applying(CGAffineTransform(scaleX: scale, y: scale))
        layer.bounds.size = rect.size
        layer.position = CGPoint(x: hinge.x * scale, y: hinge.y * scale)
        bodyMask.frame = CGRect(x: 0, y: 0, width: size, height: size)
        let outline = CGMutablePath()
        outline.addRect(bodyMask.bounds)
        outline.addRect(rect)
        bodyMask.path = outline
    }

    func update(cell: CGRect, wagging: Bool) {
        if wagging {
            layer.contentsRect = CGRect(x: cell.minX + cell.width * tail.minX / cellSize,
                                        y: cell.minY + cell.height * tail.minY / cellSize,
                                        width: cell.width * tail.width / cellSize,
                                        height: cell.height * tail.height / cellSize)
        }
        guard layer.isHidden == wagging else { return }
        layer.isHidden = !wagging
        if wagging {
            let wag = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            wag.values = [0, -0.72, 0, 0.80, 0]
            wag.duration = 0.9
            wag.repeatCount = .infinity
            wag.calculationMode = .cubic
            layer.add(wag, forKey: "wag")
        } else {
            layer.removeAnimation(forKey: "wag")
        }
    }
}
