/// What the cat says when it is poked, in several languages.
public enum CatHiss {
    public struct Phrase: Equatable, Sendable {
        /// BCP 47 language tag, e.g. `ko`.
        public let language: String
        public let text: String
    }

    public static let phrases: [Phrase] = [
        Phrase(language: "ko", text: "하악!"),
        Phrase(language: "en", text: "Hiss!"),
        Phrase(language: "ja", text: "シャーッ!"),
        Phrase(language: "zh", text: "哈——!"),
        Phrase(language: "de", text: "Fauch!"),
        Phrase(language: "fr", text: "Pfff !"),
        Phrase(language: "es", text: "¡Fffff!"),
        Phrase(language: "ru", text: "Шшш!"),
    ]

    /// A random phrase index that differs from the previous one, so consecutive pokes always
    /// sound different. `random` is injectable for tests.
    public static func nextIndex(
        after previous: Int?,
        random: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) -> Int {
        guard let previous, phrases.indices.contains(previous), phrases.count > 1 else {
            return random(0..<phrases.count)
        }
        // Pick among the others, then skip over the previous slot.
        let pick = random(0..<(phrases.count - 1))
        return pick >= previous ? pick + 1 : pick
    }
}
