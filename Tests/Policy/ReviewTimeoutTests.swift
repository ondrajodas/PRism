import Foundation
import Testing

@testable import PRism

/// Časový limit běhu revieweera (#320) — meze, sráření a hláška o hodnotě mimo ně.
///
/// **Nejcennější tvrzení je o tom, že se nic nezměnilo**: výchozích patnáct minut je hodnota,
/// se kterou aplikace běžela do #320, a zavedení nastavení ji nesmí posunout. Porovnává se proto
/// s **číslem**, ne s `ReviewTimeout.standardMinutes` — konstanta sama se sebou projde i po
/// přepsání.
///
/// Druhá polovina je o tom, že **„bez limitu“ neexistuje**: žádná hodnota, kterou jde do souboru
/// napsat, hlídání nevypne. Vyčerpávající výčet je tu levný, protože je to čistá funkce nad `Int`.
@Suite("Policy — časový limit běhu (#320)")
struct ReviewTimeoutTests {
    // MARK: - Co se nesmělo změnit

    /// Patnáct minut je to, co bylo do #320 v `ClaudeReviewRunner.defaultTimeout`.
    @Test("Výchozí limit je pořád patnáct minut")
    func theDefaultDidNotMove() {
        #expect(ReviewTimeout.standardMinutes == 15)
        #expect(ReviewTimeout.standard == .seconds(900))
        // A druhá strana téhož: výchozí konfigurace tu hodnotu doopravdy nese, takže se běh
        // s nedotčeným `config.json` chová jako před #320.
        #expect(Configuration.standard.global.reviewTimeoutMinutes == 15)
        #expect(Policy.reviewTimeout(minutes: Configuration.standard.global.reviewTimeoutMinutes)
            == .seconds(900))
        // A dojde to až do toho, co se předává běhu.
        #expect(Configuration.standard.resolved(
            for: RepoID(owner: "cli", name: "cli")
        ).reviewTimeout == .seconds(900))
    }

    /// Výchozí hodnota **je uvnitř** povoleného rozsahu. Kdyby nebyla, srazila by se — a aplikace
    /// by po zavedení pole běžela s jiným limitem než před ním, aniž by to kdokoli napsal.
    @Test("Výchozí hodnota leží uvnitř mezí")
    func theDefaultIsInsideTheRange() {
        #expect(ReviewTimeout.allowedMinutes.contains(ReviewTimeout.standardMinutes))
        #expect(Policy.reviewTimeoutMinutes(from: ReviewTimeout.standardMinutes) == 15)
        #expect(Policy.reviewTimeoutProblem(in: ReviewTimeout.standardMinutes) == nil)
    }

    // MARK: - Meze

    @Test("Meze jsou pět a šedesát minut")
    func theBoundsAreFiveAndSixty() {
        #expect(ReviewTimeout.minimumMinutes == 5)
        #expect(ReviewTimeout.maximumMinutes == 60)
        #expect(ReviewTimeout.allowedMinutes == 5...60)
    }

    /// Vyčerpávající výčet přes hranice i mimo ně. „Bez limitu“ nejde nastavit **ničím** — ani
    /// nulou, ani zápornou hodnotou, ani `Int.max`.
    @Test(
        "Hodnota mimo meze se srazí dovnitř",
        arguments: [
            (Int.min, 5),
            (-1, 5),
            (0, 5),
            (1, 5),
            (4, 5),
            (5, 5),
            (6, 6),
            (15, 15),
            (59, 59),
            (60, 60),
            (61, 60),
            (600, 60),
            (Int.max, 60),
        ]
    )
    func valuesOutsideTheRangeAreClamped(configured: Int, expected: Int) {
        #expect(Policy.reviewTimeoutMinutes(from: configured) == expected)
        #expect(Policy.reviewTimeout(minutes: configured) == .seconds(expected * 60))
    }

    /// Nula je zrovna ta hodnota, kterou si někdo napíše ve smyslu „nehlídej to“. Že z ní vyjde
    /// dolní mez, a ne vypnuté hlídání, je celé to pravidlo.
    @Test("Nula ani záporná hodnota hlídání nevypne")
    func zeroDoesNotDisableTheLimit() {
        #expect(Policy.reviewTimeout(minutes: 0) > .zero)
        #expect(Policy.reviewTimeout(minutes: -30) > .zero)
        #expect(Policy.reviewTimeout(minutes: 0) == Policy.reviewTimeout(minutes: 5))
    }

    // MARK: - Hláška

    @Test(
        "Uvnitř mezí není o čem mluvit",
        arguments: [5, 6, 15, 30, 59, 60]
    )
    func valuesInsideTheRangeHaveNoProblem(configured: Int) {
        #expect(Policy.reviewTimeoutProblem(in: configured) == nil)
    }

    @Test("Kratší než mez se pozná a nese, kolik je v souboru")
    func aTooShortValueIsNamed() throws {
        let problem = try #require(Policy.reviewTimeoutProblem(in: 2))
        #expect(problem == .tooShort(configured: 2))
        #expect(problem.configured == 2)
        #expect(problem.applied == 5)
        // Věta musí nést obě čísla **i důvod** — „mimo rozsah“ samo o sobě je jen zákaz.
        #expect(problem.reason.contains("2 min"))
        #expect(problem.reason.contains("5 min"))
        #expect(problem.reason.contains("6,8 min"))
    }

    @Test("Delší než mez se pozná a řekne, že „bez limitu“ nejde")
    func aTooLongValueIsNamed() throws {
        let problem = try #require(Policy.reviewTimeoutProblem(in: 240))
        #expect(problem == .tooLong(configured: 240))
        #expect(problem.configured == 240)
        #expect(problem.applied == 60)
        #expect(problem.reason.contains("240 min"))
        #expect(problem.reason.contains("60 min"))
        #expect(problem.reason.contains("bez limitu"))
    }

    /// Hláška a chování musí mluvit o **témže čísle**. Dvě místa, kde se sráží, by se rozešla —
    /// a v okně by stálo jedno, běželo by druhé.
    @Test(
        "Co hláška slibuje, to se doopravdy použije",
        arguments: [Int.min, -5, 0, 3, 4, 61, 120, Int.max]
    )
    func theComplaintMatchesTheAppliedValue(configured: Int) throws {
        let problem = try #require(Policy.reviewTimeoutProblem(in: configured))
        #expect(Policy.reviewTimeoutMinutes(from: configured) == problem.applied)
    }
}
