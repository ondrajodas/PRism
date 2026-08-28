import Foundation
import Testing

@testable import PRism

/// Relace v zásuvce (#460) — kdo smí vzniknout, co kvůli tomu odejde a co je vidět v hlavičce.
///
/// Je to `Policy`, takže výčtem a bez mockování. **Nejcennější je tvrzení o tom, co se nestane:
/// běžící relace se nikdy nevytlačí.** Zahodit rozdělaný `claude --resume` kvůli kliknutí, které
/// o něm nic neví, je nevratný omyl — a rozbije se to potichu, protože zásuvka po tom vypadá jako
/// by se nic nestalo.
@Suite("Zásuvka — relace (#460)")
struct TerminalSlotsTests {
    private let pr = PRIdentifier("cli/cli#42")!
    private let other = PRIdentifier("cli/cli#43")!

    private func slot(_ skill: String, in pullRequest: PRIdentifier? = nil) -> TerminalSlot {
        TerminalSlot(pullRequest: pullRequest ?? pr, role: .session(skill))
    }

    private var shell: TerminalSlot { TerminalSlot(pullRequest: pr, role: .shell) }

    // MARK: - Klíč

    /// **Klíčem je dvojice, ne jen skill**: pracovní adresář je adresář *toho* pull requestu,
    /// takže relace stejného jména na dvou PR jsou dvě různé věci a nesmí se potkat v mapě.
    @Test("Táž dráha na jiném PR je jiná relace")
    func theSameLaneOnAnotherPullRequestIsAnotherSlot() {
        #expect(slot("php-review") != slot("php-review", in: other))
        #expect(shell != TerminalSlot(pullRequest: other, role: .shell))
        #expect(shell != slot("php-review"))
    }

    // MARK: - Strop

    @Test("Do stropu se relace přidávají bez vytlačení")
    func belowTheLimitNothingIsEvicted() {
        let slots = [shell]

        #expect(
            Policy.terminalSlotAdmission(of: slot("php-review"), in: slots, states: [:])
                == .added(evicting: nil)
        )
    }

    /// Relace, kterou zásuvka **už má**, se neotevírá znovu — jen se na ni přepne.
    @Test("Existující relace se jen ukáže")
    func anExistingSlotIsOnlyShown() {
        let slots = [shell, slot("php-review")]

        #expect(
            Policy.terminalSlotAdmission(of: slot("php-review"), in: slots, states: [:]) == .existing
        )
    }

    /// **Vytlačuje se nejstarší neběžící**, protože zahodit doběhlou relaci stojí jen její výpis.
    @Test("Plný strop vytlačí nejstarší doběhlou relaci")
    func theOldestIdleSlotIsEvicted() {
        let slots = [shell, slot("a"), slot("b"), slot("c"), slot("d")]
        var states: [TerminalSlot: TerminalRunState] = [:]
        for slot in slots { states[slot] = .running }
        states[slot("b")] = .exited(code: 0)

        #expect(
            Policy.terminalSlotAdmission(of: slot("nova"), in: slots, states: states)
                == .added(evicting: slot("b"))
        )
    }

    /// **Nejcennější tvrzení téhle suity**: když všechny běží, nová relace **nevznikne**.
    /// Vytlačit běžící `claude --resume` by byl nevratný omyl.
    @Test("Když všechny relace běží, žádná se nevytlačí")
    func arunningSlotIsNeverEvicted() {
        let slots = [shell, slot("a"), slot("b"), slot("c"), slot("d")]
        var states: [TerminalSlot: TerminalRunState] = [:]
        for slot in slots { states[slot] = .running }

        #expect(Policy.terminalSlotAdmission(of: slot("nova"), in: slots, states: states) == .refused)
    }

    /// Relace, o které se nikdy nic nehlásilo, **neběží** — a smí se tedy vytlačit. Bez toho by
    /// zásuvka po restartu tvrdila, že je plná něčím, co v ní nikdy nebylo.
    @Test("Relace bez hlášeného stavu se za běžící nepovažuje")
    func aslotWithoutAStateCountsAsIdle() {
        let slots = [shell, slot("a"), slot("b"), slot("c"), slot("d")]

        #expect(
            Policy.terminalSlotAdmission(of: slot("nova"), in: slots, states: [:])
                == .added(evicting: shell)
        )
    }

    /// Strop je pět: `maxConcurrentReviews` je ve výchozí konfiguraci tři, k tomu holý shell —
    /// tedy čtyři jsou stav, do kterého se dá dojít běžným používáním.
    @Test("Strop je pět a je nad výchozím počtem paralelních review")
    func thelimitLeavesRoomForTheDefaultParallelism() {
        #expect(Policy.maxTerminalSlots == 5)
        #expect(Policy.maxTerminalSlots > Configuration.standard.global.maxConcurrentReviews)
    }

    /// Nesmyslný strop nesmí vyrobit zásuvku, do které se nevejde nic.
    @Test("Nulový strop se bere jako jedna relace")
    func azeroLimitStillHoldsOne() {
        #expect(
            Policy.terminalSlotAdmission(of: slot("a"), in: [], states: [:], limit: 0)
                == .added(evicting: nil)
        )
    }

    // MARK: - Pořadí

    /// **Pořadí je pořadí vzniku** — přepínač se nemá přeskládat pod rukama jen proto, že se
    /// někam kliklo.
    @Test("Nová relace jde na konec, vytlačená z výčtu zmizí")
    func theOrderIsTheOrderOfCreation() {
        let slots = [shell, slot("a"), slot("b")]

        #expect(
            Policy.terminalSlots(slots, adding: slot("c"), evicting: slot("a"))
                == [shell, slot("b"), slot("c")]
        )
        #expect(Policy.terminalSlots(slots, adding: shell, evicting: nil) == slots)
    }

    /// Po zániku aktivní relace se vybírá **poslední zbylá**, ne první: relace přibývají na konec,
    /// takže poslední je ta, ke které se člověk dostal naposledy.
    @Test("Po zániku relace zbyde ta poslední")
    func theLastSlotTakesOver() {
        let slots = [shell, slot("a"), slot("b")]

        #expect(Policy.terminalSlotAfterRemoval(of: slot("b"), from: slots) == slot("a"))
        #expect(Policy.terminalSlotAfterRemoval(of: shell, from: [shell]) == nil)
    }

    // MARK: - Co je v hlavičce vidět

    /// U session **jméno dráhy, ne `session_id`** (návrh, sekce 35).
    @Test("Na záložce je jméno dráhy, u shellu slovo shell")
    func thetabCarriesTheLaneName() {
        #expect(Policy.terminalSlotTitle(.shell) == "shell")
        #expect(Policy.terminalSlotTitle(.session("php-review")) == "php-review")
    }

    /// **Tři stavy puntíku, i když návrh kreslí dva** — do #460 stála v hlavičce kapsle
    /// `skončil (kód)` a nenulový konec se nesmí ztratit.
    @Test("Puntík rozlišuje běh, nenulový konec a klid")
    func themarkTellsTheThreeStatesApart() {
        #expect(Policy.terminalSlotMark(.running) == .running)
        #expect(Policy.terminalSlotMark(.exited(code: 130)) == .failed)
        #expect(Policy.terminalSlotMark(.exited(code: 0)) == .idle)
        // Kód, který nedorazil, **není chyba** — je to odpověď „nevíme“, a červený puntík by
        // tvrdil víc, než data unesou.
        #expect(Policy.terminalSlotMark(.exited(code: nil)) == .idle)
        #expect(Policy.terminalSlotMark(nil) == .idle)
    }

    /// **Návratový kód žije v nápovědě**, protože do puntíku se nevejde a s víc relacemi se tři
    /// kódy do hlavičky nevejdou taky.
    @Test("Nápověda nese celý stav včetně kódu")
    func thehelpCarriesTheExitCode() {
        #expect(Policy.terminalSlotHelp("php-review", state: .running) == "php-review — běží")
        #expect(Policy.terminalSlotHelp("php-review", state: .exited(code: 130)).contains("130"))
        #expect(Policy.terminalSlotHelp("shell", state: nil).contains("zatím nic neběželo"))
        #expect(Policy.terminalSlotHelp("shell", state: .exited(code: nil)).contains("nedorazil"))
    }

    @Test("Záložky nesou stav každé relace zvlášť")
    func therowsCarryEachStateOnItsOwn() {
        let rows = Policy.terminalSlotRows(
            [shell, slot("php-review")],
            active: slot("php-review"),
            states: [shell: .running, slot("php-review"): .exited(code: 1)]
        )

        #expect(rows.map(\.title) == ["shell", "php-review"])
        #expect(rows.map(\.mark) == [.running, .failed])
        #expect(rows.map(\.isActive) == [false, true])
    }

    /// Bez aktivní relace **není zvýrazněná žádná** — zásuvka se v tom stavu nekreslí, ale
    /// hlavička by jinak tvrdila, že se něco dívá na první.
    @Test("Bez aktivní relace není zvýrazněná žádná")
    func withoutAnActiveSlotNothingIsHighlighted() {
        let rows = Policy.terminalSlotRows([shell, slot("a")], active: nil, states: [:])

        #expect(rows.allSatisfy { !$0.isActive })
    }

    // MARK: - Věta o plné zásuvce

    /// Mlčky nevzniklá záložka vypadá jako rozbité tlačítko, takže se to **musí říct** — a věta
    /// musí obsahovat i to, co s tím.
    @Test("Plná zásuvka se řekne i s cestou ven")
    func afullDrawerIsExplained() {
        let notice = Policy.slotsFullNotice("php-review")

        #expect(notice.contains("php-review"))
        #expect(notice.contains("\(Policy.maxTerminalSlots)"))
        #expect(notice.contains("Ukonči"))
    }
}
