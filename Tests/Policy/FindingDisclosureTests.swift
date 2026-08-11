import Foundation
import Testing

@testable import PRism

/// Kdy je nález u kódu rozbalený (#185).
///
/// Je to čistá funkce, takže se testuje výčtem: blokující, ostatní, odmítnutý, překliknutý —
/// a hlavně to, co se stát **nemá** (odmítnutý se nerozbalí ani po kliknutí, shoda nerozbaluje).
@Suite("Policy — rozbalení nálezu")
struct FindingDisclosureTests {
    private func group(_ findings: [Finding], dismissed: [Finding] = []) -> FindingGroup {
        FindingGroup(
            file: findings.first?.file ?? dismissed.first?.file,
            line: findings.first?.line ?? dismissed.first?.line,
            findings: findings + dismissed,
            dismissals: makeDismissals(dismissed)
        )
    }

    private func blocking(_ summary: String = "nález", reviewer: String = "code-review") -> Finding {
        makeFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .confirmed,
            summary: summary,
            reviewer: reviewer
        )
    }

    private func quiet(_ summary: String = "nález", reviewer: String = "code-review") -> Finding {
        makeFinding(
            file: "Cart.swift",
            line: 13,
            category: "style",
            verdict: .confirmed,
            summary: summary,
            reviewer: reviewer
        )
    }

    // MARK: - Výchozí stav

    @Test("Blokující nález je rozbalený rovnou")
    func pinsABlockingFinding() {
        #expect(Policy.disclosure(of: group([blocking()])) == .expanded)
    }

    @Test("Ostatní jsou značka na hraně řádku")
    func collapsesTheRest() {
        #expect(Policy.disclosure(of: group([quiet()])) == .collapsed)
        // `PLAUSIBLE` v blokující kategorii neblokuje (`isBlocking`), takže se taky sbalí —
        // jinak by „možná“ přišpendlilo bublinu stejně jako potvrzený nález.
        #expect(Policy.disclosure(of: group([makeFinding(
            file: "Cart.swift",
            line: 13,
            category: "correctness",
            verdict: .plausible
        )])) == .collapsed)
    }

    /// Blokující sada je per repo, takže si o přišpendlení rozhoduje konfigurace, ne konstanta.
    @Test("Rozhoduje blokující sada z konfigurace")
    func honoursTheConfiguredCategories() {
        #expect(Policy.disclosure(of: group([quiet()]), categories: ["style"]) == .expanded)
        #expect(Policy.disclosure(of: group([blocking()]), categories: ["style"]) == .collapsed)
    }

    /// Stačí **jeden** blokující ve skupině: bublina je jedna a nedá se rozbalit napůl.
    @Test("Jeden blokující ve skupině rozbalí celou bublinu")
    func oneBlockingFindingPinsTheWholeGroup() {
        #expect(Policy.disclosure(of: group([quiet("první"), blocking("druhý")])) == .expanded)
    }

    // MARK: - Co se stát nemá

    /// Shoda dvou reviewerů je odznak, ne důvod k rozbalení: přišpendlení je o tom, co zastaví
    /// merge, kdežto shoda o tom, jak moc nálezu věřit.
    @Test("Shoda 2× sama nerozbaluje")
    func agreementDoesNotPin() {
        let agreed = group([
            quiet("první", reviewer: "code-review"),
            quiet("druhý", reviewer: "swift-review"),
        ])

        #expect(agreed.agreement == 2)
        #expect(Policy.disclosure(of: agreed) == .collapsed)
    }

    @Test("Odmítnutá skupina se nerozbalí ani po překliknutí")
    func neverExpandsADismissedGroup() {
        let finding = blocking()
        let dismissed = group([], dismissed: [finding])

        #expect(Policy.disclosure(of: dismissed) == .dismissed)
        #expect(
            Policy.disclosure(of: dismissed, toggled: [Policy.disclosureKey(of: dismissed)]) == .dismissed
        )
    }

    /// Odmítnutí blokujícího nálezu bublinu **sbalí**: nález, kterému nevěřím, není důvod, aby
    /// mi zabíral řádky v diffu.
    @Test("Odmítnutý blokující nález bublinu odpřišpendlí")
    func unpinsWhenTheBlockingFindingIsDismissed() {
        let quietOne = quiet("platí")
        let blockingOne = blocking("neplatí")

        let mixed = group([quietOne], dismissed: [blockingOne])

        #expect(Policy.disclosure(of: mixed) == .collapsed)
    }

    // MARK: - Překliknutí

    @Test("Překliknutí rozbalí sbalený a sbalí rozbalený")
    func togglesBothWays() {
        let quietGroup = group([quiet()])
        let blockingGroup = group([blocking()])
        let toggled: Set<String> = [Policy.disclosureKey(of: quietGroup)]

        #expect(Policy.disclosure(of: quietGroup, toggled: toggled) == .expanded)
        // Klíč je stejný (`file:line`), takže tatáž hodnota v množině sbalí i blokující.
        #expect(Policy.disclosure(of: blockingGroup, toggled: toggled) == .collapsed)
    }

    @Test("Překliknutí cizího místa s bublinou nehne")
    func ignoresTogglesOfOtherPlaces() {
        #expect(Policy.disclosure(of: group([quiet()]), toggled: ["Cart.swift|14"]) == .collapsed)
    }

    // MARK: - Klíč

    /// Klíč nese **místo**, ne text nálezu: `summary` si reviewer v dalším běhu přeformuluje,
    /// a rozbalení by se tím tiše vrátilo do výchozího stavu.
    @Test("Klíč je místo a nemění se s nálezy na něm")
    func keysByPlace() {
        let one = group([quiet("první")])
        let two = group([quiet("jinak napsané"), blocking("a ještě jeden")])

        #expect(Policy.disclosureKey(of: one) == "Cart.swift|13")
        #expect(Policy.disclosureKey(of: one) == Policy.disclosureKey(of: two))
        // A odmítnutí jednoho z nich s klíčem taky nehne.
        #expect(Policy.disclosureKey(of: group([quiet("první")], dismissed: [blocking()])) == "Cart.swift|13")
    }

    /// Nález bez řádku místo nemá a k jednomu souboru jich může být víc, takže tam klíč nese
    /// identitu nálezu — jinak by se rozbalením jednoho otevřely všechny.
    @Test("Nálezy bez řádku mají každý svůj klíč")
    func keysFindingsWithoutALineApart() {
        let first = makeFinding(file: "Cart.swift", summary: "chybí testy")
        let second = makeFinding(file: "Cart.swift", summary: "chybí dokumentace")

        let keys = Set([first, second].map { Policy.disclosureKey(of: group([$0])) })

        #expect(keys.count == 2)
    }

    /// Skupiny **s** řádkem a **bez** řádku se nesmí trefit do jednoho klíče, i když jsou ve
    /// stejném souboru.
    @Test("Klíč skupiny bez řádku se nesejde s klíčem místa")
    func doesNotCollideWithAPlaceKey() {
        let withoutLine = group([makeFinding(file: "Cart.swift", summary: "chybí testy")])

        #expect(Policy.disclosureKey(of: withoutLine) != Policy.disclosureKey(of: group([quiet()])))
    }
}
