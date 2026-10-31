import AppKit
import LangCursorCore

/// The menu bar icon and its settings menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettings = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    var onAlwaysOnChange: ((Bool) -> Void)?
    var keyboardAccessGranted: (() -> Bool)?

    var alwaysOn = false {
        didSet { alwaysOnItem.state = alwaysOn ? .on : .off }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let alwaysOnItem = NSMenuItem(
        title: "항상 켜져 있기",
        action: #selector(toggleAlwaysOn),
        keyEquivalent: ""
    )
    private let permissionItem = NSMenuItem(
        title: "입력 모니터링 권한 허용…",
        action: #selector(openPermissionSettings),
        keyEquivalent: ""
    )

    override init() {
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        alwaysOnItem.target = self
        permissionItem.target = self

        menu.addItem(alwaysOnItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    func show(_ language: InputLanguage) {
        statusItem.button?.title = language.label
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.isHidden = keyboardAccessGranted?() ?? false
    }

    @objc private func toggleAlwaysOn() {
        alwaysOn.toggle()
        onAlwaysOnChange?(alwaysOn)
    }

    @objc private func openPermissionSettings() {
        NSWorkspace.shared.open(Self.inputMonitoringSettings)
    }
}
