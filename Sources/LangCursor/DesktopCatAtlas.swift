import AppKit
import ImageIO
import LangCursorCore
import QuartzCore

/// A single GPU texture for every animation. Frames are never decoded or cropped on a tick.
@MainActor
final class DesktopCatAtlas {
    static let columns = 8
    static let rows = 8

    let image: CGImage

    init() throws {
        guard let url = Bundle.module.url(forResource: "CatSpriteAtlas", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              image.width.isMultiple(of: Self.columns),
              image.height.isMultiple(of: Self.rows),
              image.width / Self.columns == image.height / Self.rows else {
            throw AtlasError.invalidResource
        }
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

    private let sprite = CALayer()
    private let atlas: DesktopCatAtlas
    private var renderedPose: CatPose?

    init(atlas: DesktopCatAtlas, size: CGFloat) {
        self.atlas = atlas
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        sprite.contents = atlas.image
        sprite.contentsGravity = .resize
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.isOpaque = false
        layer?.addSublayer(sprite)
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
        sprite.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        sprite.position = CGPoint(x: size / 2, y: size / 2)
        CATransaction.commit()
    }

    func render(_ pose: CatPose) {
        // Position is updated separately; an idle tick does not touch the texture.
        if let renderedPose,
           renderedPose.animation == pose.animation,
           renderedPose.frame == pose.frame,
           renderedPose.mirrored == pose.mirrored { return }
        renderedPose = pose
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contentsRect = atlas.contentsRect(for: pose)
        sprite.setAffineTransform(CGAffineTransform(scaleX: pose.mirrored ? -1 : 1, y: 1))
        CATransaction.commit()
    }
}
