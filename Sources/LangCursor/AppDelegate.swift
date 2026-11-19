import AppKit
import LangCursorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let alwaysOnKey = "alwaysOn"
    private static let catEnabledKey = "desktopCatEnabled"
    private static let catSizeKey = "desktopCatSize"
    private static let hungerDelayKey = "desktopCatHungerDelay"
    private static let poopDelayKey = "desktopCatPoopDelay"

    private let overlay = OverlayWindow()
    private let inputSource = InputSourceMonitor()
    private let keyboard = KeyboardMonitor()
    private let mouse = MouseMonitor()
    private let statusMenu = StatusMenu()
    private let desktopCat = DesktopCatController()

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
        UserDefaults.standard.register(defaults: [
            Self.catEnabledKey: true, Self.catSizeKey: 64.0,
            Self.hungerDelayKey: 60.0, Self.poopDelayKey: 10.0,
        ])
        let catEnabled = UserDefaults.standard.bool(forKey: Self.catEnabledKey)
        let catSize = UserDefaults.standard.double(forKey: Self.catSizeKey)
        desktopCat.setSize(catSize)
        desktopCat.setEnabled(catEnabled)
        statusMenu.catEnabled = catEnabled
        statusMenu.catSize = catSize
        statusMenu.onCatEnabledChange = { [weak self] enabled in
            UserDefaults.standard.set(enabled, forKey: Self.catEnabledKey)
            self?.desktopCat.setEnabled(enabled)
        }
        statusMenu.onCatSizeChange = { [weak self] size in
            UserDefaults.standard.set(size, forKey: Self.catSizeKey)
            self?.desktopCat.setSize(size)
        }
        let hungerDelay = UserDefaults.standard.double(forKey: Self.hungerDelayKey)
        let poopDelay = UserDefaults.standard.double(forKey: Self.poopDelayKey)
        desktopCat.setHungerDelay(hungerDelay)
        desktopCat.setPoopDelay(poopDelay)
        statusMenu.hungerDelay = hungerDelay
        statusMenu.poopDelay = poopDelay
        statusMenu.onHungerDelayChange = { [weak self] seconds in
            UserDefaults.standard.set(seconds, forKey: Self.hungerDelayKey)
            self?.desktopCat.setHungerDelay(seconds)
        }
        statusMenu.onPoopDelayChange = { [weak self] seconds in
            UserDefaults.standard.set(seconds, forKey: Self.poopDelayKey)
            self?.desktopCat.setPoopDelay(seconds)
        }
        statusMenu.poopCount = { [weak self] in self?.desktopCat.poopCount ?? 0 }
        statusMenu.onCleanAllPoops = { [weak self] in self?.desktopCat.cleanAllPoops() }
        desktopCat.start()

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

    func applicationWillTerminate(_ notification: Notification) {
        desktopCat.stop()
        hideWork?.cancel()
        if let appNapGuard { ProcessInfo.processInfo.endActivity(appNapGuard) }
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
