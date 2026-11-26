import Testing
@testable import LangCursorCore

@Suite struct CatNeedsTests {
    @Test func hungerAndDroppingsAreOffByDefault() {
        var needs = CatNeeds(now: 0)
        needs.update(now: 1000, catArrived: true)
        #expect(needs.errand == .none)
        let dropped = needs.shouldPoop(now: 1000, catResting: true, poopCount: 0)
        #expect(!dropped)
    }

    @Test func randomDroppingsRepeatWithoutMovementAndWaitForAvailableSpace() {
        var needs = CatNeeds(now: 50, poopDelay: CatNeeds.randomDelay)
        var previous = 50.0
        for _ in 0..<5 {
            needs.recordActivity(at: previous + 599)
            let tooSoon = needs.shouldPoop(now: previous + 599, catResting: true, poopCount: 0)
            #expect(!tooSoon)
            let noRoom = needs.shouldPoop(now: previous + 1200, catResting: true, poopCount: 5)
            #expect(!noRoom)
            let moving = needs.shouldPoop(now: previous + 1250, catResting: false, poopCount: 0)
            #expect(!moving)
            previous += 1300
            let dropped = needs.shouldPoop(now: previous, catResting: true, poopCount: 0)
            #expect(dropped)
            let duplicate = needs.shouldPoop(now: previous, catResting: true, poopCount: 0)
            #expect(!duplicate)
        }
    }

    @Test func randomMealsRepeatFromTheEndOfEatingIndependentlyOfDroppings() {
        var needs = CatNeeds(now: 0, hungerDelay: CatNeeds.randomDelay)
        var previousMeal = 0.0
        for _ in 0..<5 {
            needs.setPoopDelay(CatNeeds.randomDelay, now: previousMeal + 500)
            needs.recordActivity(at: previousMeal + 599)
            needs.update(now: previousMeal + 599, catArrived: false)
            #expect(needs.errand == .none)
            needs.update(now: previousMeal + 1200, catArrived: false)
            #expect(needs.errand == .leaving)
            let cancelled = needs.recordActivity(at: previousMeal + 1201)
            #expect(!cancelled)
            needs.update(now: previousMeal + 1202, catArrived: true)
            let served = needs.serveFood(at: previousMeal + 1203)
            #expect(served)
            previousMeal += 1203 + CatNeeds.eatingDuration
            needs.update(now: previousMeal, catArrived: true)
            #expect(needs.errand == .none)
        }
    }

    @Test func randomSchedulesStartFreshOnEnableAndDoNotCatchUpAfterResume() {
        var needs = CatNeeds(now: 0)
        needs.setPoopDelay(CatNeeds.randomDelay, now: 2000)
        needs.setHungerDelay(CatNeeds.randomDelay, now: 2000)
        needs.restartTimers(at: 10000)
        needs.update(now: 10599, catArrived: false)
        #expect(needs.errand == .none)
        let early = needs.shouldPoop(now: 10599, catResting: true, poopCount: 0)
        #expect(!early)
        needs.setPoopDelay(0, now: 10600)
        let disabled = needs.shouldPoop(now: 12000, catResting: true, poopCount: 0)
        #expect(!disabled)
    }

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
