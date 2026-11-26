import Foundation

enum PetSpecies: Int, CaseIterable {
    case cat, dog, hamster

    var atlasName: String {
        switch self {
        case .cat: "CatSpriteAtlas"
        case .dog: "DogSpriteAtlas"
        case .hamster: "HamsterSpriteAtlas"
        }
    }

    var title: String {
        switch self {
        case .cat: "고양이"
        case .dog: "강아지"
        case .hamster: "햄스터"
        }
    }
}

/// Values in the original preferences domain keep their existing keys and units.
enum Preference: String, CaseIterable {
    case petEnabled = "desktopCatEnabled"
    case species = "desktopPetSpecies"
    case size = "desktopCatSize"
    case followDelay = "desktopPetFollowDelayMilliseconds"
    case idle = "desktopPetIdleAnimations"
    case reaction = "desktopPetClickReaction"
    case hunger = "desktopCatHungerDelay"
    case poop = "desktopCatPoopDelay"
    case lifetime = "desktopPoopLifetime"
    case flies = "desktopPoopFlies"
    case badge = "inputBadgeEnabled"
    case alwaysOn
    case language = "menuLanguage"

    var value: Int {
        if let number = UserDefaults.standard.object(forKey: rawValue) as? NSNumber {
            return number.intValue
        }
        switch self {
        case .petEnabled, .idle, .reaction: return 1
        case .size: return 64
        case .followDelay: return 1800
        case .lifetime: return 30
        default: return 0
        }
    }

    static func migrateLegacyBadge() {
        if UserDefaults.standard.object(forKey: Preference.badge.rawValue) == nil, Preference.alwaysOn.enabled {
            Preference.badge.save(1)
        }
    }

    func save(_ value: Int) {
        UserDefaults.standard.set(value, forKey: rawValue)
    }

    var enabled: Bool { value != 0 }
}

struct MenuLanguagePack {
    // The menu lists each language in its own script, even after switching languages.
    static let languages = [
        ("", "시스템 언어"), ("ko", "한국어"), ("en", "English"), ("cn", "简体中文"),
        ("ja", "日本語"), ("es", "Español"), ("fr", "Français"),
    ]
    private let strings: [String: [String: String]]

    init() {
        if let url = Bundle.module.url(forResource: "MenuLanguages", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let translations = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            strings = translations
        } else {
            strings = [:]
            NSLog("Could not load MenuLanguages.json")
        }
    }

    func text(_ key: String, language: String) -> String {
        strings[key]?[language] ?? key
    }

    static func selectedCode() -> String {
        let choice = Preference.language.value
        if choice > 0, languages.indices.contains(choice) { return languages[choice].0 }
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            if code == "zh" { return "cn" }
            if let code, languages.contains(where: { $0.0 == code }) { return code }
        }
        return "en"
    }
}
