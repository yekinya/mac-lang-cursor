/// Recognizes key events that may switch the input language, without waiting for the
/// system to confirm the switch.
public enum ToggleKey {
    private static let space: UInt16 = 49

    /// Modifier-style keys, reported through `flagsChanged`:
    /// Caps Lock, Fn, Globe, and right Command/Option (common remap targets).
    private static let modifierKeys: Set<UInt16> = [57, 63, 179, 54, 61]

    /// Regular keys, reported through `keyDown`:
    /// the JIS Eisu/Kana codes used by language keys, and F13–F20 (common remap targets).
    private static let languageKeys: Set<UInt16> = [
        102, 104,
        105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public static func isModifierToggle(keyCode: UInt16) -> Bool {
        modifierKeys.contains(keyCode)
    }

    public static func isKeyDownToggle(keyCode: UInt16, controlHeld: Bool) -> Bool {
        languageKeys.contains(keyCode) || (keyCode == space && controlHeld)
    }
}
