@preconcurrency import Carbon
import AppKit
import LangCursorCore

/// Tracks the selected keyboard input source.
@MainActor
final class InputSourceMonitor: NSObject {
    /// Polling sees a switch about 10–15 ms before the notification arrives, and costs
    /// under a microsecond per read, so it is worth doing right after a toggle key.
    private static let pollInterval = DispatchTimeInterval.milliseconds(5)
    private static let pollCount = 100

    private(set) var current = InputSourceMonitor.read()
    var onChange: ((InputLanguage) -> Void)?

    private var pollTimer: DispatchSourceTimer?
    private var pollsRemaining = 0

    func start() {
        // Without .deliverImmediately, a background app's delivery is deferred.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func inputSourceChanged() {
        refresh()
    }

    func refresh() {
        let latest = Self.read()
        guard latest != current else { return }
        current = latest
        onChange?(latest)
    }

    /// Polls briefly, picking up a switch sooner than the notification would.
    func watchForSwitch() {
        pollsRemaining = Self.pollCount
        guard pollTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
        pollTimer = timer
        timer.resume()
    }

    private func poll() {
        refresh()
        pollsRemaining -= 1
        if pollsRemaining <= 0 {
            pollTimer?.cancel()
            pollTimer = nil
        }
    }

    private static func read() -> InputLanguage {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let id: CFString? = property(of: source, kTISPropertyInputSourceID)
        let languages: CFArray? = property(of: source, kTISPropertyInputSourceLanguages)
        return InputLanguage(
            sourceID: (id as String?) ?? "",
            languages: (languages as? [String]) ?? []
        )
    }

    private static func property<Value: AnyObject>(
        of source: TISInputSource,
        _ key: CFString
    ) -> Value? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<Value>.fromOpaque(pointer).takeUnretainedValue()
    }
}
