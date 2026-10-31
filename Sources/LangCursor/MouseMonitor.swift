import AppKit

/// Reports cursor movement. Global mouse monitors need no permission.
@MainActor
final class MouseMonitor {
    var onMove: (() -> Void)?

    private var monitor: Any?

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onMove?() }
        }
    }
}
