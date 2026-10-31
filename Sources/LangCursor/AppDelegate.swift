import AppKit
import LangCursorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let alwaysOnKey = "alwaysOn"

    private let overlay = OverlayWindow()
    private let inputSource = InputSourceMonitor()
    private let keyboard = KeyboardMonitor()
    private let mouse = MouseMonitor()
    private let statusMenu = StatusMenu()

    private var policy = VisibilityPolicy()
    private var hideWork: DispatchWorkItem?
    private var appNapGuard: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hidden menu bar app is eligible for App Nap, which would delay the overlay.
        appNapGuard = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Reacting to input source changes without delay"
        )

        policy.alwaysOn = UserDefaults.standard.bool(forKey: Self.alwaysOnKey)

        statusMenu.alwaysOn = policy.alwaysOn
        statusMenu.show(inputSource.current)
        statusMenu.keyboardAccessGranted = { [keyboard] in keyboard.isRunning }
        statusMenu.onAlwaysOnChange = { [weak self] in self?.setAlwaysOn($0) }

        inputSource.onChange = { [weak self] language in
            guard let self else { return }
            statusMenu.show(language)
            registerActivity()
        }
        keyboard.onActivity = { [weak self] in self?.handleKeyboardActivity() }
        keyboard.onToggleKey = { [weak self] in self?.handleToggleKey() }
        mouse.onMove = { [weak self] in self?.registerActivity() }

        inputSource.start()
        keyboard.start()
        mouse.start()
        registerActivity()
    }

    private func handleKeyboardActivity() {
        inputSource.refresh()
        registerActivity()
    }

    /// Shows the overlay before the switch lands, then watches closely for it, so that a
    /// swallowed switch is visible as the language simply staying the same.
    private func handleToggleKey() {
        registerActivity()
        inputSource.watchForSwitch()
    }

    private func registerActivity() {
        let now = ProcessInfo.processInfo.systemUptime
        policy.recordActivity(at: now)
        overlay.show(inputSource.current)
        scheduleHide()
    }

    private func setAlwaysOn(_ enabled: Bool) {
        policy.alwaysOn = enabled
        UserDefaults.standard.set(enabled, forKey: Self.alwaysOnKey)
        registerActivity()
    }

    /// Runs at most once per idle period. Activity arriving meanwhile only moves the
    /// deadline, which `hideIfIdle` picks up when it fires.
    private func scheduleHide() {
        guard hideWork == nil, let hideTime = policy.hideTime else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hideWork = nil
            hideIfIdle()
        }
        hideWork = work
        let delay = hideTime - ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0), execute: work)
    }

    private func hideIfIdle() {
        let now = ProcessInfo.processInfo.systemUptime
        if policy.isVisible(at: now) {
            scheduleHide()
        } else {
            overlay.hide()
        }
    }
}
