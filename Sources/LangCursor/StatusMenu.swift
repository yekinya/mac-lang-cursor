import AppKit
import LangCursorCore

/// The menu bar icon and its settings menu.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private static let inputMonitoringSettings = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    var onAlwaysOnChange: ((Bool) -> Void)?
    var onCatEnabledChange: ((Bool) -> Void)?
    var onCatSizeChange: ((CGFloat) -> Void)?
    var onHungerDelayChange: ((TimeInterval) -> Void)?
    var onPoopDelayChange: ((TimeInterval) -> Void)?
    var onCleanAllPoops: (() -> Void)?
    var poopCount: (() -> Int)?
    var keyboardAccessGranted: (() -> Bool)?

    var alwaysOn = false {
        didSet { alwaysOnItem.state = alwaysOn ? .on : .off }
    }
    var catEnabled = true {
        didSet { catEnabledItem.state = catEnabled ? .on : .off }
    }
    var catSize: CGFloat = 64 {
        didSet {
            for item in catSizeItems { item.state = CGFloat(item.tag) == catSize ? .on : .off }
        }
    }

    var hungerDelay: TimeInterval = 60 {
        didSet { Self.check(hungerItems, value: hungerDelay) }
    }
    var poopDelay: TimeInterval = 10 {
        didSet { Self.check(poopItems, value: poopDelay) }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let alwaysOnItem = NSMenuItem(
        title: "항상 켜져 있기",
        action: #selector(toggleAlwaysOn),
        keyEquivalent: ""
    )
    private let catEnabledItem = NSMenuItem(
        title: "바탕화면 고양이",
        action: #selector(toggleCat),
        keyEquivalent: ""
    )
    private var catSizeItems: [NSMenuItem] = []
    private var hungerItems: [NSMenuItem] = []
    private var poopItems: [NSMenuItem] = []
    private let cleanPoopsItem = NSMenuItem(
        title: "똥 모두 치우기",
        action: #selector(cleanAllPoops),
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
        catEnabledItem.target = self
        catEnabledItem.state = .on
        permissionItem.target = self

        menu.addItem(catEnabledItem)
        let sizeItem = NSMenuItem(title: "고양이 크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (title, points) in [("아주 작게", 48), ("작게 (기본)", 64), ("보통", 80)] {
            let item = NSMenuItem(title: title, action: #selector(changeCatSize(_:)), keyEquivalent: "")
            item.tag = points
            item.target = self
            item.state = points == 64 ? .on : .off
            sizeMenu.addItem(item)
            catSizeItems.append(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        hungerItems = addChoiceMenu(
            to: menu, title: "배고파지는 시간",
            choices: [("30초", 30), ("1분 (기본)", 60), ("3분", 180), ("5분", 300), ("10분", 600), ("끄기", 0)],
            selected: hungerDelay, action: #selector(changeHungerDelay(_:))
        )
        poopItems = addChoiceMenu(
            to: menu, title: "가만히 있으면 똥 싸기",
            choices: [("10초 뒤 (기본)", 10), ("30초 뒤", 30), ("1분 뒤", 60), ("3분 뒤", 180), ("끄기", 0)],
            selected: poopDelay, action: #selector(changePoopDelay(_:))
        )
        cleanPoopsItem.target = self
        menu.addItem(cleanPoopsItem)
        menu.addItem(.separator())
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
        let count = poopCount?() ?? 0
        cleanPoopsItem.title = count > 0 ? "똥 모두 치우기 (\(count)개)" : "똥 모두 치우기"
        cleanPoopsItem.isEnabled = count > 0
    }

    @objc private func toggleAlwaysOn() {
        alwaysOn.toggle()
        onAlwaysOnChange?(alwaysOn)
    }

    @objc private func toggleCat() {
        catEnabled.toggle()
        onCatEnabledChange?(catEnabled)
    }

    @objc private func changeCatSize(_ sender: NSMenuItem) {
        catSize = CGFloat(sender.tag)
        onCatSizeChange?(catSize)
    }

    @objc private func changeHungerDelay(_ sender: NSMenuItem) {
        hungerDelay = TimeInterval(sender.tag)
        onHungerDelayChange?(hungerDelay)
    }

    @objc private func cleanAllPoops() {
        onCleanAllPoops?()
    }

    @objc private func changePoopDelay(_ sender: NSMenuItem) {
        poopDelay = TimeInterval(sender.tag)
        onPoopDelayChange?(poopDelay)
    }

    /// A submenu of radio-style choices whose tags hold seconds.
    private func addChoiceMenu(
        to menu: NSMenu, title: String, choices: [(String, Int)],
        selected: TimeInterval, action: Selector
    ) -> [NSMenuItem] {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        var items: [NSMenuItem] = []
        for (label, seconds) in choices {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.tag = seconds
            item.target = self
            submenu.addItem(item)
            items.append(item)
        }
        Self.check(items, value: selected)
        parent.submenu = submenu
        menu.addItem(parent)
        return items
    }

    private static func check(_ items: [NSMenuItem], value: TimeInterval) {
        for item in items { item.state = TimeInterval(item.tag) == value ? .on : .off }
    }

    @objc private func openPermissionSettings() {
        NSWorkspace.shared.open(Self.inputMonitoringSettings)
    }
}
