import Foundation
import Testing

@testable import PRism

/// Odznak v Docku (#529) — **výčtem, protože je to jedno číslo, které nikdo nekontroluje**.
///
/// Dlaždice v Docku je vidět zrovna tehdy, když se do aplikace nikdo nedívá, takže špatné číslo
/// v ní se nepozná porovnáním s railem — nikdo se nekouká na obojí naráz. Sada proto tvrdí obě
/// věci naráz: co se má nakreslit, a **co se nakreslit nesmí** (nula, „nevím“, vypnuto).
@Suite("Policy — odznak v Docku (#529)")
struct DockBadgeTests {
    private func summary(_ identifier: String) -> PullRequestSummary {
        let id = PRIdentifier(identifier)!
        return PullRequestSummary(
            id: id,
            title: "titulek",
            author: "kolega",
            url: URL(string: "https://github.com/\(id.repo)/pull/\(id.number)")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            state: .open
        )
    }

    /// Pět cizích PR, z nich dva s blokujícím nálezem — tatáž trojice čísel jako v návrhu.
    private var queue: [PullRequestSummary] {
        (1...5).map { summary("cli/cli#\($0)") }
    }

    private func blocking(_ numbers: Set<Int>) -> (PRIdentifier) -> Bool {
        { numbers.contains($0.number) }
    }

    @Test("Čekající kreslí počet cizích PR ve frontě")
    func drawsTheQueueCount() {
        #expect(Policy.dockBadge(.waiting, queue: queue, isBlocking: blocking([1, 2])) == "5")
    }

    /// **Blokující je tatáž množina, jen zúžená** — proto se počítá z toho samého pole. Kdyby se
    /// bralo ze souhrnu fronty (`queueSummary`), který filtr ignoruje, umělo by přepnutí volby
    /// ukázat **větší** číslo než `čekající`.
    @Test("Blokující počítá z těch samých PR")
    func drawsTheBlockingSubsetOfTheSameQueue() {
        #expect(Policy.dockBadge(.blocking, queue: queue, isBlocking: blocking([1, 2])) == "2")
    }

    /// Invariant celého issue: **blokující ≤ čekající**, a to nad každou podmnožinou. Kdyby se ta
    /// dvě čísla brala ze dvou různých množin, tenhle test by se dal obejít jen shodou okolností.
    @Test("Blokující nikdy nevyjde větší než čekající", arguments: [
        Set<Int>(), Set([3]), Set([1, 2]), Set([1, 2, 3, 4, 5]), Set([7, 8]),
    ])
    func neverExceedsTheQueue(_ marked: Set<Int>) {
        let waiting = Policy.dockBadge(.waiting, queue: queue, isBlocking: blocking(marked))
        let blocked = Policy.dockBadge(.blocking, queue: queue, isBlocking: blocking(marked))

        // `nil` je nula, takže se porovnávají čísla, ne řetězce.
        #expect((Int(blocked ?? "0") ?? 0) <= (Int(waiting ?? "0") ?? 0))
    }

    /// **Nula se nekreslí.** Odznak `0` by v systémové červené hlásil poplach nad ničím — prázdná
    /// fronta je dobrá zpráva, ne položka k vyřízení. Rail to dělá stejně.
    @Test("Prázdná fronta nekreslí nic", arguments: [DockBadgeMode.waiting, .blocking, .off])
    func drawsNothingOverAnEmptyQueue(_ mode: DockBadgeMode) {
        #expect(Policy.dockBadge(mode, queue: [], isBlocking: blocking([])) == nil)
    }

    /// Fronta bez blokujícího nálezu je u volby `blokující` **taky prázdná** — a je to tentýž
    /// stav jako prázdná fronta, ne jiný.
    @Test("Fronta bez blokujícího nálezu nekreslí nic")
    func drawsNothingWithoutABlockingFinding() {
        #expect(Policy.dockBadge(.blocking, queue: queue, isBlocking: blocking([])) == nil)
    }

    /// **„Nevím“ kreslí totéž co prázdno, a je to rozhodnutí** (poznámka 179 v návrhu): dlaždice
    /// má jeden kanál, takže se do ní věta „seznam ještě nedorazil“ napsat nedá. Nenačtený seznam
    /// pozná stavový řádek v okně.
    @Test("Nenačtený seznam nekreslí nic", arguments: [DockBadgeMode.waiting, .blocking, .off])
    func drawsNothingBeforeTheFirstTick(_ mode: DockBadgeMode) {
        #expect(Policy.dockBadge(mode, queue: nil, isBlocking: blocking([1, 2])) == nil)
    }

    /// Vypnuto znamená **prázdný odznak, ne nulu** — a `nic` je opravdu nic, i nad plnou frontou.
    @Test("Volba nic nekreslí nic ani nad plnou frontou")
    func drawsNothingWhenTurnedOff() {
        #expect(Policy.dockBadge(.off, queue: queue, isBlocking: blocking([1, 2])) == nil)
    }

    /// **Tvrzení, že se něco NEstalo**: ve výchozí volbě se na uložené nálezy vůbec nesáhne.
    /// Kdyby se sáhlo, sledoval by odznak mapu `reviewRecords` a probouzel se na každé změně
    /// záznamu i tehdy, když o nálezech nemluví.
    @Test("U čekající a nic se na nálezy neptá", arguments: [DockBadgeMode.waiting, .off])
    func neverAsksAboutFindingsOutsideTheBlockingMode(_ mode: DockBadgeMode) {
        final class Counter {
            var asked = 0
        }
        let counter = Counter()

        _ = Policy.dockBadge(mode, queue: queue) { _ in
            counter.asked += 1
            return true
        }

        #expect(counter.asked == 0)
    }

    /// U `blokující` se naopak zeptá **na každý PR ve frontě, právě jednou** — druhý průchod by
    /// znamenal dvojí čtení uložených záznamů při každém překreslení.
    @Test("U blokující se zeptá jednou na každý PR")
    func asksOncePerPullRequestInTheBlockingMode() {
        final class Log {
            var seen: [Int] = []
        }
        let log = Log()

        _ = Policy.dockBadge(.blocking, queue: queue) { pr in
            log.seen.append(pr.number)
            return false
        }

        #expect(log.seen == [1, 2, 3, 4, 5])
    }

    /// Volba se čte z konfigurace, takže se **nesmí ztratit rozbitou hodnotou**: neznámý řetězec
    /// znamená výchozí `čekající`, ne prázdný odznak. Tolerantně jako vzhled a pohled na diff.
    @Test("Rozbitá volba v souboru skončí na čekající")
    func fallsBackToWaitingOnABrokenValue() throws {
        let json = #"{"global": {"dockBadge": "všechno", "mode": "manual"}}"#
        let configuration = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))

        #expect(configuration.global.dockBadge == .waiting)
        // Zbytek souboru překlep nezahodil — je to tolerantní čtení, ne zámek.
        #expect(configuration.global.mode == .manual)
    }

    /// Chybějící klíč je **zapnuto**, tedy chování, které #529 přináší: aplikace, která hlídá, má
    /// být vidět i zavřená, a knoflík, o kterém se nikdo nedozví, by to nesplnil.
    @Test("Chybějící klíč znamená čekající")
    func defaultsToWaiting() throws {
        let configuration = try JSONDecoder().decode(
            Configuration.self,
            from: Data(#"{"global": {"mode": "manual"}}"#.utf8)
        )

        #expect(configuration.global.dockBadge == .waiting)
        #expect(Configuration.standard.global.dockBadge == .waiting)
    }

    /// Popisky v přepínači jsou ty z návrhu — segment, který se přejmenuje, přestane odpovídat
    /// větě pod ním.
    @Test("Popisky segmentů jsou ty z návrhu")
    func keepsTheLabelsFromTheDesign() {
        #expect(DockBadgeMode.allCases.map(\.title) == ["čekající", "blokující", "nic"])
        #expect(DockBadgeMode.allCases.map(\.rawValue) == ["waiting", "blocking", "off"])
    }
}
