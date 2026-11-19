import Testing
@testable import LangCursorCore

@Suite struct CatNeedsTests {
    private func waitingCat() -> CatNeeds {
        var needs = CatNeeds(now: 0, hungerDelay: 30, poopDelay: 0)
        needs.update(now: 30, catArrived: false)
        needs.update(now: 35, catArrived: true)
        needs.update(now: 40, catArrived: true)
        return needs
    }

    @Test func getsHungryOnlyAfterTheCursorStaysStillForTheDelay() {
        var needs = CatNeeds(now: 0, hungerDelay: 60)
        needs.update(now: 59.9, catArrived: true)
        #expect(needs.errand == .none)
        needs.update(now: 60, catArrived: false)
        #expect(needs.errand == .leaving)
        #expect(!needs.showsBowl)
    }

    @Test func movementRestartsTheHungerCountdown() {
        var needs = CatNeeds(now: 0, hungerDelay: 60)
        needs.recordActivity(at: 50)
        needs.update(now: 100, catArrived: false)
        #expect(needs.errand == .none)
        needs.update(now: 110, catArrived: false)
        #expect(needs.errand == .leaving)
    }

    @Test func fetchesAnEmptyBowlThenWaitsBesideIt() {
        var needs = CatNeeds(now: 0, hungerDelay: 30)
        needs.update(now: 30, catArrived: false)
        needs.update(now: 35, catArrived: true)
        #expect(needs.errand == .returning)
        #expect(needs.showsBowl)
        #expect(needs.bowlAcceptsFood)
        needs.update(now: 36, catArrived: false)
        #expect(needs.errand == .returning)
        needs.update(now: 40, catArrived: true)
        #expect(needs.errand == .waiting)
        #expect(needs.bowlAcceptsFood)
        #expect(needs.foodLeft(now: 40) == 0)
        needs.update(now: 400, catArrived: true)
        #expect(needs.errand == .waiting)
    }

    @Test func movementCallsOffOnlyAFetchThatHasNoBowlYet() {
        var leaving = CatNeeds(now: 0, hungerDelay: 30)
        do { let result = leaving.recordActivity(at: 1); #expect(!result) }
        leaving.update(now: 31, catArrived: false)
        do { let result = leaving.recordActivity(at: 32); #expect(result) }
        #expect(leaving.errand == .none)

        var waiting = waitingCat()
        do { let result = waiting.recordActivity(at: 41); #expect(!result) }
        #expect(waiting.errand == .waiting)
    }

    @Test func servingFoodStartsAMealThatEmptiesTheBowl() {
        var needs = waitingCat()
        do { let result = needs.serveFood(at: 50); #expect(result) }
        #expect(needs.errand == .eating)
        #expect(!needs.bowlAcceptsFood)
        #expect(needs.foodLeft(now: 50) == 1)
        #expect(needs.foodLeft(now: 53) == 0.5)
        #expect(needs.eatingTime(now: 53) == 3)
        do { let result = needs.serveFood(at: 51); #expect(!result) }
        needs.update(now: 55.9, catArrived: true)
        #expect(needs.errand == .eating)
        needs.update(now: 56, catArrived: true)
        #expect(needs.errand == .none)
        #expect(!needs.showsBowl)
    }

    @Test func aFullCatWaitsAnotherWholeDelayBeforeGettingHungry() {
        var needs = waitingCat()
        needs.serveFood(at: 50)
        needs.update(now: 56, catArrived: true)
        needs.update(now: 85, catArrived: true)
        #expect(needs.errand == .none)
        needs.update(now: 86, catArrived: true)
        #expect(needs.errand == .leaving)
    }

    @Test func servesFoodOnlyOnceTheCatHasTheBowl() {
        var needs = CatNeeds(now: 0, hungerDelay: 30)
        do { let result = needs.serveFood(at: 1); #expect(!result) }
        needs.update(now: 30, catArrived: false)
        #expect(needs.errand == .leaving)
        do { let result = needs.serveFood(at: 31); #expect(!result) }
        needs.update(now: 35, catArrived: true)
        // Still carrying it: a click serves food right away.
        do { let result = needs.serveFood(at: 36); #expect(result) }
        #expect(needs.errand == .eating)
        #expect(needs.foodLeft(now: 36) == 1)
    }

    @Test func zeroDelayDisablesHungerAndChangingItCancelsTheErrand() {
        var needs = waitingCat()
        needs.setHungerDelay(0, now: 50)
        #expect(needs.errand == .none)
        needs.update(now: 10_000, catArrived: true)
        #expect(needs.errand == .none)
    }

    @Test func changingTheDelayCountsFromNow() {
        var needs = CatNeeds(now: 0, hungerDelay: 600)
        needs.setHungerDelay(30, now: 100)
        needs.update(now: 129, catArrived: false)
        #expect(needs.errand == .none)
        needs.update(now: 130, catArrived: false)
        #expect(needs.errand == .leaving)
    }

    @Test func poopsOnceAfterTheCursorIsStillForTheDelay() {
        var needs = CatNeeds(now: 0, hungerDelay: 0, poopDelay: 10)
        do { let result = needs.shouldPoop(now: 9.9, catResting: true, poopCount: 0); #expect(!result) }
        do { let result = needs.shouldPoop(now: 10, catResting: true, poopCount: 0); #expect(result) }
        do { let result = needs.shouldPoop(now: 100, catResting: true, poopCount: 1); #expect(!result) }
        needs.recordActivity(at: 100)
        do { let result = needs.shouldPoop(now: 109, catResting: true, poopCount: 1); #expect(!result) }
        do { let result = needs.shouldPoop(now: 110, catResting: true, poopCount: 1); #expect(result) }
    }

    @Test func dueDroppingWaitsUntilTheCatRestsAndThereIsRoom() {
        var needs = CatNeeds(now: 0, hungerDelay: 0, poopDelay: 10)
        do { let result = needs.shouldPoop(now: 12, catResting: false, poopCount: 0); #expect(!result) }
        do { let result = needs.shouldPoop(now: 13, catResting: true, poopCount: CatNeeds.maxPoops); #expect(!result) }
        do { let result = needs.shouldPoop(now: 14, catResting: true, poopCount: CatNeeds.maxPoops - 1); #expect(result) }
    }

    @Test func doesNotPoopDuringAnErrand() {
        var needs = CatNeeds(now: 0, hungerDelay: 5, poopDelay: 10)
        needs.update(now: 5, catArrived: false)
        do { let result = needs.shouldPoop(now: 20, catResting: true, poopCount: 0); #expect(!result) }
    }

    @Test func zeroDelayDisablesPooping() {
        var needs = CatNeeds(now: 0, hungerDelay: 0, poopDelay: 10)
        needs.setPoopDelay(0)
        do { let result = needs.shouldPoop(now: 10_000, catResting: true, poopCount: 0); #expect(!result) }
    }
}
