import Foundation
import Testing

@testable import PRism

@Suite("Policy — procházení nálezů")
struct FindingNavigationTests {
    private func group(
        _ file: String?,
        _ line: Int?,
        category: String = "style",
        dismissed: Bool = false
    ) -> FindingGroup {
        let finding = makeFinding(
            file: file,
            line: line,
            category: category,
            verdict: .confirmed,
            summary: "\(file ?? "—"):\(line.map(String.init) ?? "—")"
        )
        return FindingGroup(
            file: file,
            line: line,
            findings: [finding],
            dismissals: dismissed ? makeDismissals([finding]) : [:]
        )
    }

    private func place(_ file: String, _ line: Int?) -> FindingPlace? {
        FindingPlace(group(file, line))
    }

    @Test("Nález a jeho skupina dají totéž místo")
    func aFindingAndItsGroupShareThePlace() {
        // Na tomhle stojí zvýraznění karty v panelu (#175): kurzor se plní ze skupiny, ale
        // karta se ptá za jednotlivý nález. Kdyby se ta dvě místa rozešla, lišta by skákala
        // jinam, než co je v panelu označené — a nikdo by nepoznal proč.
        let finding = makeFinding(file: "a.php", line: 10)
        let group = FindingGroup(file: "a.php", line: 10, findings: [finding])

        #expect(FindingPlace(finding) == FindingPlace(group))
        // A nález bez místa v kódu žádné místo nedá — do procházení nepatří.
        #expect(FindingPlace(makeFinding(file: nil, line: nil)) == nil)
    }

    @Test("Bez kurzoru se jde dopředu, ne dozadu")
    func withoutACursorOnlyForwardIsPossible() {
        // První skok má vzít první nález, ne poslední.
        let groups = [group("a.php", 10), group("b.php", 20)]
        let navigation = Policy.navigation(over: groups, cursor: FindingCursor())

        #expect(navigation.position == nil)
        #expect(navigation.total == 2)
        #expect(navigation.hasNext)
        #expect(!navigation.hasPrevious)
        #expect(Policy.step(.forward, over: groups, cursor: FindingCursor()) == place("a.php", 10))
        // A zkratka `⌥↑` musí poslechnout totéž, co lišta ukazuje: šipka nahoru je zhasnutá,
        // takže krok dozadu nesmí skočit na poslední místo. Tlačítko a klávesa se nesmí
        // rozejít — jedno by pak dělalo něco, co druhé tvrdí, že nejde.
        #expect(Policy.step(.backward, over: groups, cursor: FindingCursor()) == nil)
    }

    @Test("Kurzor mimo zúžený seznam jde jen dopředu")
    func aCursorOutsideTheNarrowedListOnlyGoesForward() {
        // Zapnu `jen blokující` a kurzor stojí na nálezu, který v zúženém seznamu není:
        // dopředu se začíná od začátku, dozadu není odkud.
        let groups = [
            group("a.php", 10, category: "style"),
            group("b.php", 20, category: "correctness"),
        ]
        var cursor = FindingCursor(current: place("a.php", 10))
        cursor.onlyBlocking = true

        #expect(Policy.step(.forward, over: groups, cursor: cursor) == place("b.php", 20))
        #expect(Policy.step(.backward, over: groups, cursor: cursor) == nil)
        #expect(!Policy.navigation(over: groups, cursor: cursor).hasPrevious)
    }

    @Test("Šipky se drží pořadí v diffu")
    func arrowsFollowTheDiffOrder() {
        let groups = [group("a.php", 10), group("b.php", 20), group("c.php", 30)]
        var cursor = FindingCursor(current: place("b.php", 20))

        #expect(Policy.step(.forward, over: groups, cursor: cursor) == place("c.php", 30))
        #expect(Policy.step(.backward, over: groups, cursor: cursor) == place("a.php", 10))

        cursor.current = place("c.php", 30)
        // Na kraji není kam — tlačítko se má zhasnout, ne zacyklit.
        #expect(Policy.step(.forward, over: groups, cursor: cursor) == nil)
        #expect(!Policy.navigation(over: groups, cursor: cursor).hasNext)
    }

    @Test("Odmítnutý nález se přeskočí")
    func aDismissedFindingIsSkipped() {
        // Nález, kterému nevěřím, není práce k projití — a kdyby v řadě zůstal, „prošel jsi
        // všechno" by znamenalo i „proklikal jsi to, co jsi zamítl".
        let groups = [group("a.php", 10), group("b.php", 20, dismissed: true), group("c.php", 30)]
        let cursor = FindingCursor(current: place("a.php", 10))

        #expect(Policy.navigation(over: groups, cursor: cursor).total == 2)
        #expect(Policy.step(.forward, over: groups, cursor: cursor) == place("c.php", 30))
    }

    @Test("Nález bez místa se počítá zvlášť, ne do řady")
    func aFindingWithoutAPlaceIsCountedApart() {
        // Skočit se na něj nedá, ale zamlčet ho nejde: „1 z 1" by nad PR se dvěma nálezy
        // v panelu tvrdilo hotovo.
        let groups = [group("a.php", 10), group(nil, nil)]
        let navigation = Policy.navigation(over: groups, cursor: FindingCursor())

        #expect(navigation.total == 1)
        #expect(navigation.withoutPlace == 1)
    }

    @Test("Zúžení na blokující mění, kam se skáče")
    func narrowingToBlockingChangesTheRoute() {
        let groups = [
            group("a.php", 10, category: "style"),
            group("b.php", 20, category: "correctness"),
            group("c.php", 30, category: "style"),
        ]
        var cursor = FindingCursor(current: place("a.php", 10))
        cursor.onlyBlocking = true

        #expect(Policy.navigation(over: groups, cursor: cursor).total == 1)
        // Kurzor stojí mimo zúžený seznam, takže se začíná od začátku — jinak by se ta část,
        // kterou zúžení vybralo, přeskočila.
        #expect(Policy.step(.forward, over: groups, cursor: cursor) == place("b.php", 20))
        #expect(Policy.navigation(over: groups, cursor: cursor).position == nil)
    }

    @Test("Hotovo znamená projitá všechna místa, ne konec seznamu")
    func completeMeansEveryPlaceSeen() {
        // Přeskákat je zprostředka a skončit na posledním neznamená, že jsem viděl i ta
        // před ním — a zelený puntík je jediné místo, kde okno tvrdí hotovo.
        let groups = [group("a.php", 10), group("b.php", 20)]
        var cursor = FindingCursor(current: place("b.php", 20))
        cursor.seen = [place("b.php", 20)!]

        #expect(!Policy.navigation(over: groups, cursor: cursor).isComplete)

        cursor.seen.insert(place("a.php", 10)!)
        #expect(Policy.navigation(over: groups, cursor: cursor).isComplete)
    }

    @Test("Prázdný seznam nic netvrdí")
    func anEmptyListClaimsNothing() {
        // Nula míst není „prošel jsi všechno" — není co procházet.
        let navigation = Policy.navigation(over: [], cursor: FindingCursor())

        #expect(!navigation.isComplete)
        #expect(navigation.isEmpty)
        #expect(Policy.step(.forward, over: [], cursor: FindingCursor()) == nil)
    }

    @Test("Ztracené místo pod kurzorem shodí pozici, ne seznam")
    func aLostPlaceOnlyClearsThePosition() {
        // Nálezy se pod rukama mění: doběhne další reviewer, nález se odmítne. Kurzor pak
        // ukazuje jinam — ukázat „4 ze 3" je horší než přiznat, že nikde nestojím.
        let groups = [group("a.php", 10)]
        let cursor = FindingCursor(current: place("zmizelo.php", 99))
        let navigation = Policy.navigation(over: groups, cursor: cursor)

        #expect(navigation.position == nil)
        #expect(navigation.total == 1)
        #expect(navigation.hasNext)
        #expect(Policy.step(.forward, over: groups, cursor: cursor) == place("a.php", 10))
    }

    @Test("Skupina bez platného nálezu z řady vypadne celá")
    func aGroupWithoutActiveFindingsDisappears() {
        let groups = [group("a.php", 10, dismissed: true)]

        #expect(Policy.navigation(over: groups, cursor: FindingCursor()).total == 0)
        #expect(Policy.navigablePlaces(in: groups).isEmpty)
    }
}
