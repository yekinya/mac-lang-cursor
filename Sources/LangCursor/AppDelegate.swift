import AppKit
import LangCursorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayWindow()
    private let inputSource = InputSourceMonitor()
    private let keyboard = KeyboardMonitor()
    private let mouse = MouseMonitor()
    private let statusMenu = StatusMenu()
    private let desktopCat = DesktopCatController()

    private var badgeEnabled = false
    private var policy = VisibilityPolicy()
    private var hideWork: DispatchWorkItem?
    private var appNapGuard: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hidden menu bar app is eligible for App Nap, which would delay the overlay.
        appNapGuard = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Reacting to input source changes without delay"
        )

        statusMenu.onChange = { [weak self] setting in self?.apply(setting) }
        statusMenu.poopCount = { [weak self] in self?.desktopCat.poopCount ?? 0 }
        statusMenu.onCleanAllPoops = { [weak self] in self?.desktopCat.cleanAllPoops() }
        statusMenu.keyboardAccessGranted = { [keyboard] in keyboard.isRunning }
        desktopCat.reactionText = { [statusMenu] key in statusMenu.text(key) }

        inputSource.onChange = { [weak self] language in
            guard let self else { return }
            statusMenu.show(language)
            registerActivity()
        }
        keyboard.onActivity = { [weak self] in self?.handleKeyboardActivity() }
        keyboard.onToggleKey = { [weak self] in self?.handleToggleKey() }
        mouse.onMove = { [weak self] in self?.registerActivity() }

        for setting in Preference.allCases { apply(setting) }
        desktopCat.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        desktopCat.stop()
        hideWork?.cancel()
        if let appNapGuard { ProcessInfo.processInfo.endActivity(appNapGuard) }
    }

    private func apply(_ setting: Preference) {
        switch setting {
        case .petEnabled: desktopCat.setEnabled(setting.enabled)
        case .species: desktopCat.setSpecies(PetSpecies(rawValue: setting.value) ?? .cat)
        case .size: desktopCat.setSize(CGFloat(setting.value))
        case .followDelay: desktopCat.setFollowDelay(Double(setting.value) / 1000)
        case .idle: desktopCat.setIdleAnimations(setting.enabled)
        case .reaction: desktopCat.setClickReaction(setting.enabled)
        case .hunger: desktopCat.setHungerDelay(Double(setting.value))
        case .poop: desktopCat.setPoopDelay(Double(setting.value))
        case .lifetime: desktopCat.setPoopLifetime(Double(setting.value))
        case .flies: desktopCat.setFliesEnabled(setting.enabled)
        case .badge:
            badgeEnabled = setting.enabled
            if badgeEnabled {
                inputSource.start()
                inputSource.refresh()
                statusMenu.show(inputSource.current)
                mouse.start()
                keyboard.start()
                registerActivity()
            } else {
                inputSource.stop()
                mouse.stop()
                keyboard.stop()
                hideWork?.cancel()
                hideWork = nil
                overlay.hide()
                statusMenu.show(nil)
            }
        case .alwaysOn:
            policy.alwaysOn = setting.enabled
            registerActivity()
        case .language: break
        }
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
        guard badgeEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        policy.recordActivity(at: now)
        overlay.show(inputSource.current)
        scheduleHide()
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
