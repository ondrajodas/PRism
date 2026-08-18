import Foundation
import Testing

@testable import PRism

/// Strop řádků na blok dashboardu a cíle karet (#371). Čisté funkce, takže výčtem a bez mockování.
///
/// Dvě věci se tu dají pokazit potichu: **patka, která se rozejde s kresbou** („+8“ nad šesti
/// nakreslenými řádky vypadá platně) a **karta `Dneska stálo`, která by někam vedla** — o té by se
/// zjistilo, že vede, až kliknutím.
@Suite("Blok dashboardu")
struct DashboardBlockTests {
    private func entry(_ number: Int) -> QueueEntry {
        let id = PRIdentifier(repo: RepoID("cli/cli")!, number: number)
        return QueueEntry(
            pullRequest: PullRequestSummary(
                id: id,
                title: "PR \(number)",
                author: "kdosi",
                url: URL(string: "https://github.com/cli/cli/pull/\(number)")!,
                updatedAt: Date(timeIntervalSince1970: 1_000_000),
                state: .open
            ),
            state: .notStarted,
            row: .empty,
            hasDraft: false
        )
    }

    private func entries(_ count: Int) -> [QueueEntry] {
        (1...count).map(entry)
    }

    // MARK: - Strop

    @Test("Blok nad stropem kreslí pět řádků a shrne zbytek")
    func capsRowsAndSumsUpTheRest() {
        let block = Policy.dashboardBlock(entries(13), of: .theirs)

        #expect(block.rows.map(\.pullRequest.number) == [1, 2, 3, 4, 5])
        #expect(block.footer?.title == "Zobrazit všech 13 ve frontě")
        #expect(block.footer?.rest == "+8")
        #expect(block.footer?.section == .queue)
    }

    /// **Patka se u bloku pod stropem nekreslí.** „Zobrazit všechny“ nad seznamem, který je celý
    /// vidět, je akce, po které se nic nezmění — a v mockupu je to vidět na bloku `Moje PR`.
    @Test("Blok pod stropem patku nemá")
    func hasNoFooterBelowTheLimit() {
        let block = Policy.dashboardBlock(entries(3), of: .theirs)

        #expect(block.rows.count == 3)
        #expect(block.footer == nil)
    }

    /// **Ani při přesně pěti**: strop je „nejvýš pět“, ne „pět a pak patka“. Tady se to rozhoduje
    /// o jedničku, takže je to ten případ, na kterém se `>=` proti `>` pozná.
    @Test("Přesně pět řádků patku nedostane")
    func hasNoFooterAtExactlyTheLimit() {
        let block = Policy.dashboardBlock(entries(Policy.dashboardRowLimit), of: .theirs)

        #expect(block.rows.count == Policy.dashboardRowLimit)
        #expect(block.footer == nil)
    }

    /// O jeden nad stropem: nejmenší blok, který patku má — a `+1` v ní.
    @Test("Šestý řádek patku vyvolá")
    func addsTheFooterOneOverTheLimit() {
        let block = Policy.dashboardBlock(entries(6), of: .theirs)

        #expect(block.rows.count == 5)
        #expect(block.footer?.title == "Zobrazit všech 6 ve frontě")
        #expect(block.footer?.rest == "+1")
    }

    @Test("Prázdný blok nemá řádky ani patku")
    func handlesAnEmptyBlock() {
        let block = Policy.dashboardBlock([], of: .theirs)

        #expect(block.rows.isEmpty)
        #expect(block.footer == nil)
    }

    /// Patka vede tam, kam karta nad blokem — a mluví o té množině, které se týká.
    @Test("Blok vlastních PR vede do sekce Moje PR")
    func pointsOwnBlockToTheOwnSection() {
        let block = Policy.dashboardBlock(entries(7), of: .mine)

        #expect(block.footer?.title == "Zobrazit všech 7 vlastních")
        #expect(block.footer?.section == .mine)
    }

    /// **Strop nepřerovnává.** Pořadí rozhoduje `byUrgency`; horních pět je horních pět proto, že
    /// je někdo seřadil dřív.
    @Test("Strop je řez, ne řazení")
    func keepsTheIncomingOrder() {
        let shuffled = [entry(9), entry(2), entry(7), entry(1), entry(5), entry(3)]

        let block = Policy.dashboardBlock(shuffled, of: .theirs)

        #expect(block.rows.map(\.pullRequest.number) == [9, 2, 7, 1, 5])
    }

    /// **Počet v patce musí vyjít z nakreslených řádků**, ne z konstanty: kdyby se strop a patka
    /// počítaly každý po svém, „+8“ by nad jiným počtem řádků pořád vypadalo platně. Ověřuje se
    /// přes pásmo, protože rozejít se to umí jen v něm.
    @Test("Nakreslené a shrnuté dá dohromady celou frontu")
    func addsUpToTheWholeQueue() {
        for total in 1...20 {
            let block = Policy.dashboardBlock(entries(total), of: .theirs)
            let rest = Int(block.footer?.rest.dropFirst() ?? "0") ?? 0

            #expect(block.rows.count + rest == total)
            #expect(block.rows.count <= Policy.dashboardRowLimit)
        }
    }

    // MARK: - Kam karta vede

    @Test("Každá karta vede tam, kam patří")
    func routesEveryCard() {
        #expect(Policy.destination(of: .queue) == .section(.queue))
        #expect(Policy.destination(of: .blocking) == .blockingQueue)
        #expect(Policy.destination(of: .mine) == .section(.mine))
        #expect(Policy.destination(of: .drafts) == .section(.drafts))
    }

    /// **`Dneska stálo` nevede nikam** — nemá kam, a karta, po které se nic nestane, je lež o tom,
    /// co okno umí. Je to nejcennější tvrzení v téhle sadě, protože se dá zrušit jedním řádkem.
    @Test("Karta Dneska stálo nevede nikam")
    func leavesTheSpendCardWithoutADestination() {
        #expect(Policy.destination(of: .spend) == nil)
    }

    /// Výčtem přes `allCases`: nová karta si musí vybrat, jestli někam vede — a tenhle test ji
    /// donutí se rozhodnout, protože jinak spadne na tom, že cíl nemá **a není to `spend`**.
    @Test("Cíl nemá právě jedna karta")
    func leavesExactlyOneCardWithoutADestination() {
        let without = DashboardCard.allCases.filter { Policy.destination(of: $0) == nil }

        #expect(without == [.spend])
    }

    /// Žádná karta nevede na `Přehled` — dashboard je `Přehled` sám, takže by to bylo kliknutí,
    /// po kterém se nic nestane.
    @Test("Žádná karta nevede na Přehled")
    func neverPointsBackToTheDashboard() {
        for card in DashboardCard.allCases {
            #expect(Policy.destination(of: card) != .section(.overview))
        }
    }

    @Test("Nápověda říká, do které sekce se přepne")
    func explainsWhereItGoes() {
        #expect(DashboardDestination.section(.mine).help == "Přepne do sekce Moje PR")
        #expect(
            DashboardDestination.blockingQueue.help
                == "Přepne do sekce Fronta a zapne filtr „jen blokující“"
        )
    }
}
