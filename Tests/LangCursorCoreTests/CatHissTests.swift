import Testing
@testable import LangCursorCore

@Suite struct CatHissTests {
    @Test func coversSeveralLanguagesIncludingKorean() {
        let languages = Set(CatHiss.phrases.map(\.language))
        #expect(languages.count == CatHiss.phrases.count)
        #expect(languages.isSuperset(of: ["ko", "en", "ja", "zh"]))
        #expect(CatHiss.phrases.first { $0.language == "ko" }?.text == "하악!")
    }

    @Test func neverRepeatsThePreviousPhraseAndCanReachEveryOther() {
        for previous in CatHiss.phrases.indices {
            var reached = Set<Int>()
            for pick in 0..<(CatHiss.phrases.count - 1) {
                let next = CatHiss.nextIndex(after: previous) { _ in pick }
                #expect(next != previous)
                #expect(CatHiss.phrases.indices.contains(next))
                reached.insert(next)
            }
            #expect(reached.count == CatHiss.phrases.count - 1)
        }
    }

    @Test func firstPokeMayUseAnyPhrase() {
        let last = CatHiss.phrases.count - 1
        #expect(CatHiss.nextIndex(after: nil) { _ in last } == last)
        #expect(CatHiss.nextIndex(after: 99) { _ in 0 } == 0)
    }
}
