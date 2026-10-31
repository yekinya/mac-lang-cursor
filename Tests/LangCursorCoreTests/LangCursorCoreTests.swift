import CoreGraphics
import Testing
@testable import LangCursorCore

@Suite struct InputLanguageTests {
    @Test func koreanTwoSet() {
        let language = InputLanguage(
            sourceID: "com.apple.inputmethod.Korean.2SetKorean",
            languages: ["ko"]
        )
        #expect(language.kind == .korean)
        #expect(language.label == "한")
    }

    @Test func abcUsesItsPrimaryLanguage() {
        let language = InputLanguage(sourceID: "com.apple.keylayout.ABC", languages: ["en", "ko"])
        #expect(language.kind == .english)
        #expect(language.label == "A")
    }

    @Test func regionSubtagIsIgnored() {
        #expect(InputLanguage(sourceID: "x", languages: ["en-GB"]).label == "A")
    }

    @Test func unknownLanguageFallsBackToItsCode() {
        #expect(InputLanguage(sourceID: "x", languages: ["fr"]).label == "FR")
    }

    @Test func missingLanguage() {
        #expect(InputLanguage(sourceID: "x", languages: []).label == "?")
    }
}

@Suite struct VisibilityPolicyTests {
    @Test func hiddenBeforeAnyActivity() {
        #expect(!VisibilityPolicy().isVisible(at: 100))
    }

    @Test func hidesFiveSecondsAfterLastActivity() {
        var policy = VisibilityPolicy()
        policy.recordActivity(at: 100)
        #expect(policy.isVisible(at: 104.9))
        #expect(!policy.isVisible(at: 105))
    }

    @Test func continuousActivityKeepsItVisible() {
        var policy = VisibilityPolicy()
        for time in stride(from: 100.0, to: 120, by: 2) {
            policy.recordActivity(at: time)
            #expect(policy.isVisible(at: time + 1))
        }
    }

    @Test func alwaysOnNeverHides() {
        var policy = VisibilityPolicy(alwaysOn: true)
        #expect(policy.isVisible(at: 0))
        policy.recordActivity(at: 100)
        #expect(policy.isVisible(at: 10_000))
        #expect(policy.hideTime == nil)
    }

    @Test func disablingAlwaysOnRestoresTheTimeout() {
        var policy = VisibilityPolicy(alwaysOn: true)
        policy.recordActivity(at: 100)
        policy.alwaysOn = false
        #expect(policy.hideTime == 105)
    }
}

@Suite struct ToggleKeyTests {
    @Test func capsLockAndGlobeAreToggles() {
        #expect(ToggleKey.isModifierToggle(keyCode: 57))
        #expect(ToggleKey.isModifierToggle(keyCode: 63))
    }

    @Test func shiftIsNotAToggle() {
        #expect(!ToggleKey.isModifierToggle(keyCode: 56))
    }

    @Test func controlSpaceIsAToggle() {
        #expect(ToggleKey.isKeyDownToggle(keyCode: 49, controlHeld: true))
    }

    @Test func plainSpaceIsNotAToggle() {
        #expect(!ToggleKey.isKeyDownToggle(keyCode: 49, controlHeld: false))
    }

    @Test func languageKeyIsAToggle() {
        #expect(ToggleKey.isKeyDownToggle(keyCode: 104, controlHeld: false))
    }

    @Test func letterIsNotAToggle() {
        #expect(!ToggleKey.isKeyDownToggle(keyCode: 0, controlHeld: false))
    }
}

@Suite struct OverlayPlacementTests {
    private let size = CGSize(width: 24, height: 22)
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func sitsRightOfTheCursor() {
        let origin = OverlayPlacement.origin(
            cursor: CGPoint(x: 500, y: 400),
            size: size,
            screen: screen
        )
        #expect(origin.x > 500)
    }

    @Test func flipsLeftAtTheRightEdge() {
        let origin = OverlayPlacement.origin(
            cursor: CGPoint(x: 995, y: 400),
            size: size,
            screen: screen
        )
        #expect(origin.x + size.width < 995)
    }

    @Test func staysOnScreenVertically() {
        let top = OverlayPlacement.origin(cursor: CGPoint(x: 500, y: 800), size: size, screen: screen)
        let bottom = OverlayPlacement.origin(cursor: CGPoint(x: 500, y: 0), size: size, screen: screen)
        #expect(top.y + size.height <= 800)
        #expect(bottom.y >= 0)
    }

    @Test func worksOnASecondaryScreenAtNegativeCoordinates() {
        let left = CGRect(x: -1000, y: 100, width: 1000, height: 800)
        let origin = OverlayPlacement.origin(cursor: CGPoint(x: -5, y: 105), size: size, screen: left)
        #expect(origin.x + size.width <= 0)
        #expect(origin.y >= 100)
    }
}
