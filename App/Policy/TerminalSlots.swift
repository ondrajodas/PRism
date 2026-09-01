import Foundation

/// Jedna relace v zásuvce (#460) — **jedno pty**.
///
/// Do #460 platilo „jedna zásuvka = jeden shell na pull request“ a `▶` do toho jednoho shellu
/// psalo. Nefungovalo to v tom stavu, kvůli kterému zásuvka vznikla: aplikace pouští review
/// **paralelně** (`maxConcurrentReviews`), takže se člověk chce dívat na dvě session naráz —
/// a jeden shell ho nutil jednu z nich ukončit, aby viděl druhou. Návrh, sekce 35.
///
/// **Klíčem je dvojice, ne jen skill**: pracovní adresář je adresář **toho** pull requestu, takže
/// relace stejného jména na dvou PR jsou dvě různé věci — a nesmí se potkat v mapě hostitele.
struct TerminalSlot: Hashable, Sendable, Identifiable {
    /// Čí ta relace je.
    ///
    /// **Holý shell je jedna z relací, ne něco vedle nich** (návrh, sekce 35): `` ⌃` `` dává
    /// právě jeho, takže by jinak musel existovat druhý mechanismus na tutéž věc.
    enum Role: Hashable, Sendable {
        /// To, co dá `` ⌃` `` — shell bez příkazu.
        case shell
        /// `claude --resume` dráhy toho skillu (`▶`).
        case session(String)
        /// Shell v tom stromě, kde **uvázl rebase** (#467) — `Otevřít v terminálu` u konfliktu.
        ///
        /// **Vlastní role, ne `shell`**, a rozhoduje o tom **adresář**: `shell` startuje ve stromě
        /// posledního review (nebo v bare klonu), kdežto tady je celý smysl v tom, že se člověk
        /// dostane do **rozdělaného rebase**. Jedna role se dvěma různými adresáři by znamenala, že
        /// se nedá poznat, kde relace doopravdy stojí — a `TerminalHost` existující ploše adresář
        /// nepřepíše, takže by popiska v hlavičce lhala.
        case rebase
    }

    let pullRequest: PRIdentifier
    let role: Role

    var id: Self { self }
}

/// Jedna záložka přepínače v hlavičce zásuvky (#460).
///
/// Skládá ji `Policy`, ne view: co je v hlavičce vidět a čím se to liší, je rozhodnutí nad daty.
struct TerminalSlotRow: Equatable, Sendable, Identifiable {
    let slot: TerminalSlot
    /// Co je na záložce napsané — `shell`, nebo jméno dráhy.
    let title: String
    /// Puntík: běží, spadlo, nebo nic.
    let mark: TerminalSlotMark
    /// Celá věta do nápovědy. Nese i **návratový kód**, který se do puntíku nevejde.
    let help: String
    let isActive: Bool

    var id: TerminalSlot { slot }
}

/// Co říká puntík u záložky (#460).
///
/// **Tři stavy, i když návrh kreslí dva** (`.term-tab .d` a `.term-tab.live .d`), a je to vědomé
/// rozšíření o jednu barvu na prvku, který nakreslený **je**: do #460 stála v hlavičce kapsle
/// `skončil (kód)` a odlišit `exit 1` od `exit 0` bylo zrovna to, kvůli čemu se na ni člověk
/// podíval. S víc relacemi se tři kódy do hlavičky nevejdou — proto puntík, ale úplně beze stopy
/// zmizet ta informace nesmí. Celý kód zůstává v nápovědě záložky.
enum TerminalSlotMark: Equatable, Sendable {
    /// Shell běží.
    case running
    /// Skončil **nenulově** — jediné, co si na první pohled žádá pozornost.
    case failed
    /// Neběží a nic se nepokazilo: skončil nulově, nebo ještě nezačal.
    case idle
}

/// Smí ta relace vzniknout? (#460)
enum TerminalSlotAdmission: Equatable, Sendable {
    /// Už existuje — jen se na ni přepne.
    case existing
    /// Přibude. `evicting` je relace, kterou kvůli stropu vytlačila; **vždycky neběžící**.
    case added(evicting: TerminalSlot?)
    /// Strop je plný a **všechny relace běží**, takže není co zahodit.
    case refused
}

extension Policy {
    // MARK: - Strop

    /// Kolik relací zásuvka unese na jeden pull request.
    ///
    /// **Pět, a jsou to dvě čísla složená dohromady.** Zdola: `maxConcurrentReviews` je ve výchozí
    /// konfiguraci **3**, a k paralelně běžícím reviewerům patří ještě holý shell — čtyři jsou tedy
    /// stav, do kterého se dá dojít běžným používáním, ne krajnost. Shora: přepínač je **řádek
    /// v hlavičce** vedle cesty a kapsle `plná práva`, a víc než pět záložek by tam ukrojilo
    /// zrovna tu cestu, kvůli které se na hlavičku kouká.
    ///
    /// **Neomezený počet by byl past**, a to nikoli kvůli paměti: každá relace je **skutečný
    /// proces**, který se musí uklidit při zavření okna (#264, #351) — a co se nedá spočítat, to
    /// se špatně uklízí i špatně vysvětluje v dialogu při ukončení.
    static let maxTerminalSlots = 5

    /// Smí ta relace vzniknout, a co kvůli ní musí odejít?
    ///
    /// **Vytlačuje se jen to, co neběží, a vždycky ta nejstarší taková.** Zahodit běžící shell by
    /// znamenalo zabít rozdělanou práci kvůli kliknutí, které o ní nic neví; zahodit doběhlou
    /// relaci stojí **jen její výpis** — a ten je z definice minulost. Když neběžící není žádná,
    /// nová relace **nevznikne** a řekne se to: mlčky nevzniklá záložka vypadá jako rozbité
    /// tlačítko.
    ///
    /// **Zavírací křížek u záložky návrh nekreslí**, takže vytlačování je jediná cesta, kterou se
    /// relace uvolňují za běhu; druhá je zavření záložky pull requestu, kde končí celý kontext.
    static func terminalSlotAdmission(
        of slot: TerminalSlot,
        in slots: [TerminalSlot],
        states: [TerminalSlot: TerminalRunState],
        limit: Int = maxTerminalSlots
    ) -> TerminalSlotAdmission {
        if slots.contains(slot) { return .existing }
        guard slots.count >= max(1, limit) else { return .added(evicting: nil) }
        guard let victim = slots.first(where: { states[$0] != .running }) else { return .refused }
        return .added(evicting: victim)
    }

    /// Seznam relací po přijetí nové. **Pořadí je pořadí vzniku** — přepínač se nemá přeskládat
    /// pod rukama jen proto, že se někam kliklo.
    static func terminalSlots(
        _ slots: [TerminalSlot],
        adding slot: TerminalSlot,
        evicting victim: TerminalSlot?
    ) -> [TerminalSlot] {
        var next = slots.filter { $0 != victim }
        if !next.contains(slot) { next.append(slot) }
        return next
    }

    // MARK: - Co je v hlavičce vidět

    /// Co je na záložce napsané.
    ///
    /// U session **jméno dráhy, ne `session_id`** (návrh, sekce 35): identifikátor v hlavičce
    /// neodpovídá na žádnou otázku, kterou si u přepínače někdo klade, a ukrojil by místo cestě.
    static func terminalSlotTitle(_ role: TerminalSlot.Role) -> String {
        switch role {
        case .shell: "shell"
        case .session(let skill): skill
        // Gitové jméno, jako u akce v panelu (#466) — `rebase` a `force push` se nepřekládají.
        case .rebase: "rebase"
        }
    }

    static func terminalSlotMark(_ state: TerminalRunState?) -> TerminalSlotMark {
        switch state {
        case .running: .running
        case .exited(let code?) where code != 0: .failed
        case .exited, nil: .idle
        }
    }

    /// Celá věta do nápovědy záložky — **tady žije návratový kód**, který se do puntíku nevejde.
    static func terminalSlotHelp(_ title: String, state: TerminalRunState?) -> String {
        switch state {
        case .running: "\(title) — běží"
        case .exited(let code?) where code != 0: "\(title) — skončil (\(code))"
        case .exited(let code?): "\(title) — skončil (\(code))"
        case .exited(nil): "\(title) — skončil, návratový kód nedorazil"
        case nil: "\(title) — zatím nic neběželo"
        }
    }

    /// Záložky přepínače tak, jak se kreslí.
    static func terminalSlotRows(
        _ slots: [TerminalSlot],
        active: TerminalSlot?,
        states: [TerminalSlot: TerminalRunState]
    ) -> [TerminalSlotRow] {
        slots.map { slot in
            let title = terminalSlotTitle(slot.role)
            return TerminalSlotRow(
                slot: slot,
                title: title,
                mark: terminalSlotMark(states[slot]),
                help: terminalSlotHelp(title, state: states[slot]),
                isActive: slot == active
            )
        }
    }

    /// Na kterou relaci se přepnout, když ta aktivní odešla. `nil` = žádná nezbyla.
    ///
    /// **Poslední zbylá, ne první**: relace přibývají na konec, takže poslední je ta, ke které se
    /// člověk dostal naposledy — a je pravděpodobnější, že o ni ještě stojí.
    static func terminalSlotAfterRemoval(of slot: TerminalSlot, from slots: [TerminalSlot]) -> TerminalSlot? {
        slots.filter { $0 != slot }.last
    }
}
