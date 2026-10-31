import AppKit
import CoreGraphics
import LangCursorCore

/// Reports keyboard activity through a listen-only event tap, which requires the Input
/// Monitoring permission. Only key codes are inspected; typed text is never read or kept.
@MainActor
final class KeyboardMonitor {
    private static let retryInterval: TimeInterval = 2

    var onActivity: (() -> Void)?
    var onToggleKey: (() -> Void)?

    private var tap: CFMachPort?

    var isRunning: Bool { tap != nil }

    /// Asks for permission if needed, and starts once it is granted.
    func start() {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        installTapWhenPermitted()
    }

    private func installTapWhenPermitted() {
        // tapCreate succeeds without permission and the tap then silently receives nothing,
        // so its result alone can't be trusted.
        guard CGPreflightListenEventAccess(), let tap = makeTap() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval) { [weak self] in
                self?.installTapWhenPermitted()
            }
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func makeTap() -> CFMachPort? {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    fileprivate func handle(_ type: CGEventType, keyCode: UInt16, controlHeld: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            report(isToggle: ToggleKey.isKeyDownToggle(keyCode: keyCode, controlHeld: controlHeld))
        case .flagsChanged:
            report(isToggle: ToggleKey.isModifierToggle(keyCode: keyCode))
        default:
            break
        }
    }

    private func report(isToggle: Bool) {
        if isToggle {
            onToggleKey?()
        } else {
            onActivity?()
        }
    }
}

private let keyboardTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if let userInfo {
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let controlHeld = event.flags.contains(.maskControl)
        // The tap's run loop source is on the main run loop.
        MainActor.assumeIsolated {
            monitor.handle(type, keyCode: keyCode, controlHeld: controlHeld)
        }
    }
    return Unmanaged.passUnretained(event)
}
