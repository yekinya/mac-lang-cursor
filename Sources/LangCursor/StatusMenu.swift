import AppKit
import LangCursorCore

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    var onChange: ((Preference) -> Void)?
    var onCleanAllPoops: (() -> Void)?
    var poopCount: (() -> Int)?
    var keyboardAccessGranted: (() -> Bool)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pack = MenuLanguagePack()
    private var language = MenuLanguagePack.selectedCode()
    private var cleanItem = NSMenuItem()
    private var permissionItem = NSMenuItem()

    override init() {
        super.init()
        buildMenu()
    }

    func text(_ key: String) -> String { pack.text(key, language: language) }

    private func buildMenu() {
        language = MenuLanguagePack.selectedCode()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        func toggle(_ title: String, _ setting: Preference) -> NSMenuItem {
            let item = menu.addItem(withTitle: text(title), action: #selector(selectValue(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = setting
            item.state = setting.enabled ? .on : .off
            item.tag = setting.enabled ? 0 : 1
            return item
        }

        func choices(_ title: String, _ setting: Preference, _ values: [(String, Int)]) {
            let parent = menu.addItem(withTitle: text(title), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: parent.title)
            for (key, value) in values {
                let item = submenu.addItem(withTitle: text(key), action: #selector(selectValue(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = setting
                item.tag = value
                item.state = setting.value == value ? .on : .off
            }
            parent.submenu = submenu
        }

        _ = toggle("바탕화면 동물", .petEnabled)
        choices("동물 선택", .species, PetSpecies.allCases.map { ($0.title, $0.rawValue) })
        choices("동물 크기", .size, [("아주 작게", 48), ("작게", 64), ("보통", 80)])
        choices("따라오기 대기 시간", .followDelay, [("짧게", 400), ("중간", 1800), ("길게", 3500)])
        _ = toggle("쉬는 동작", .idle)
        _ = toggle("클릭 반응", .reaction)
        menu.addItem(.separator())
        let randomInterval = ("켜기 (10~20분 무작위)", Int(CatNeeds.randomDelay))
        choices("배고파지는 시간", .hunger, [("끄기", 0), randomInterval, ("30초", 30), ("1분", 60), ("3분", 180), ("5분", 300), ("10분", 600)])
        choices("배변 간격", .poop, [("끄기", 0), randomInterval, ("10초", 10), ("30초", 30), ("1분", 60), ("3분", 180)])
        choices("똥 남기는 시간", .lifetime, [("잠시 후 사라지기 (5초)", 5), ("잠깐 남기기 (30초)", 30), ("사라지지 않기", 0)])
        _ = toggle("파리 표시", .flies)
        cleanItem = menu.addItem(withTitle: text("똥 모두 치우기"), action: #selector(cleanAll), keyEquivalent: "")
        cleanItem.target = self
        menu.addItem(.separator())
        _ = toggle("입력 언어 배지", .badge)
        toggle("항상 켜져 있기", .alwaysOn).isEnabled = Preference.badge.enabled
        permissionItem = menu.addItem(withTitle: text("입력 모니터링 권한 허용…"), action: #selector(openPermissions), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(.separator())
        choices("메뉴 언어", .language, MenuLanguagePack.languages.enumerated().map { ($0.element.1, $0.offset) })
        menu.addItem(withTitle: text("종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func show(_ input: InputLanguage?) {
        statusItem.button?.title = input?.label ?? ""
        statusItem.button?.image = input == nil ? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "LangCursor") : nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.isHidden = !Preference.badge.enabled || (keyboardAccessGranted?() ?? false)
        let count = poopCount?() ?? 0
        cleanItem.title = count == 0 ? text("똥 모두 치우기")
            : text("똥 모두 치우기 ({count}개)").replacingOccurrences(of: "{count}", with: String(count))
        cleanItem.isEnabled = count > 0
    }

    @objc private func selectValue(_ sender: NSMenuItem) {
        guard let setting = sender.representedObject as? Preference else { return }
        setting.save(sender.tag)
        buildMenu()
        onChange?(setting)
    }

    @objc private func cleanAll() { onCleanAllPoops?() }

    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
