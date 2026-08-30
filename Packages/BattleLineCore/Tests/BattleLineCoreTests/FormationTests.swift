import Testing
@testable import BattleLineCore

@Suite("Formation ranking")
struct FormationTests {
    @Test("Recognizes all five formation kinds")
    func recognizesKinds() {
        let wedge = FormationStrength(cards: [card(.red, 3), card(.red, 4), card(.red, 5)])
        let phalanx = FormationStrength(cards: [card(.red, 7), card(.blue, 7), card(.green, 7)])
        let battalion = FormationStrength(cards: [card(.purple, 1), card(.purple, 6), card(.purple, 10)])
        let skirmish = FormationStrength(cards: [card(.red, 4), card(.blue, 5), card(.green, 6)])
        let host = FormationStrength(cards: [card(.red, 1), card(.blue, 5), card(.green, 9)])

        #expect(wedge?.kind == .wedge)
        #expect(phalanx?.kind == .phalanx)
        #expect(battalion?.kind == .battalion)
        #expect(skirmish?.kind == .skirmish)
        #expect(host?.kind == .host)
        #expect(wedge?.total == 12)
        #expect(FormationStrength(cards: [card(.red, 1), card(.blue, 2)]) == nil)
    }

    @Test("Kind outranks sum, then sum breaks same-kind ties")
    func ordering() {
        let lowWedge = FormationStrength(cards: [card(.red, 1), card(.red, 2), card(.red, 3)])!
        let highPhalanx = FormationStrength(cards: [card(.red, 10), card(.blue, 10), card(.green, 10)])!
        let lowBattalion = FormationStrength(cards: [card(.orange, 1), card(.orange, 2), card(.orange, 10)])!
        let highBattalion = FormationStrength(cards: [card(.blue, 7), card(.blue, 9), card(.blue, 10)])!

        #expect(lowWedge > highPhalanx)
        #expect(highBattalion > lowBattalion)
        #expect(FormationKind.wedge > .phalanx)
        #expect(FormationKind.phalanx > .battalion)
        #expect(FormationKind.battalion > .skirmish)
        #expect(FormationKind.skirmish > .host)
    }
}
