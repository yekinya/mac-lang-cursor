/// The keyboard input language, reduced to what the overlay displays.
public struct InputLanguage: Equatable, Sendable {
    public enum Kind: Sendable {
        case korean, english, other
    }

    public let sourceID: String
    public let kind: Kind
    public let label: String

    /// - Parameter languages: BCP 47 codes of the input source, primary language first.
    public init(sourceID: String, languages: [String]) {
        self.sourceID = sourceID
        let primary = languages.first?.lowercased() ?? ""
        let base = primary.split(separator: "-").first.map(String.init) ?? primary

        switch base {
        case "ko":
            kind = .korean
            label = "한"
        case "en":
            kind = .english
            label = "A"
        case "ja":
            kind = .other
            label = "あ"
        case "zh":
            kind = .other
            label = "中"
        case "":
            kind = .other
            label = "?"
        default:
            kind = .other
            label = base.uppercased()
        }
    }
}
