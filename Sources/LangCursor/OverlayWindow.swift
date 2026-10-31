import AppKit
import LangCursorCore

/// The translucent language badge that follows the cursor.
@MainActor
final class OverlayWindow {
    private static let opacity: CGFloat = 0.72
    private static let height: CGFloat = 22
    private static let minWidth: CGFloat = 24
    private static let horizontalPadding: CGFloat = 12
    private static let fadeOutDuration: TimeInterval = 0.2

    private let panel: NSPanel
    private let badge = NSView()
    private let label = NSTextField(labelWithString: "")
    private var isShowing = false
    private var rendered: InputLanguage?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]

        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        panel.contentView = badge

        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
    }

    func show(_ language: InputLanguage) {
        if language != rendered {
            render(language)
            rendered = language
        }
        position()

        guard !isShowing else { return }
        isShowing = true
        setAlpha(Self.opacity, duration: 0)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        setAlpha(0, duration: Self.fadeOutDuration) { [weak self] in
            // Activity during the fade brings the overlay back; leave it on screen then.
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func setAlpha(
        _ alpha: CGFloat,
        duration: TimeInterval,
        completion: (@Sendable () -> Void)? = nil
    ) {
        // Going through the animator, even at zero duration, replaces any running fade.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    private func render(_ language: InputLanguage) {
        label.stringValue = language.label
        badge.layer?.backgroundColor = Self.color(for: language.kind).cgColor

        let width = max(
            Self.minWidth,
            ceil(label.intrinsicContentSize.width) + Self.horizontalPadding
        )
        if panel.frame.width != width {
            panel.setContentSize(NSSize(width: width, height: Self.height))
        }
    }

    private func position() {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        panel.setFrameOrigin(OverlayPlacement.origin(
            cursor: cursor,
            size: panel.frame.size,
            screen: screen.frame
        ))
    }

    private static func color(for kind: InputLanguage.Kind) -> NSColor {
        switch kind {
        case .korean: .systemBlue
        case .english: NSColor(white: 0.15, alpha: 1)
        case .other: .systemPurple
        }
    }
}
