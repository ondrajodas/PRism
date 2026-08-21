import Foundation
import Testing

@testable import PRism

/// Rozbor evaluačního zásobníku AttributeGraphu (#361).
///
/// Je to **rozbor cizího formátu**, takže se testuje nad skutečným výstupem: fixture
/// `attributegraph/stack-text.txt` je to, co vrátilo `AGGraphDescription(nil, ["format":
/// "stack/text"])` na macOS 26 uvnitř průchodu tělem řádku `LazyVStack`u. Ručně napsaný literál
/// by nesl formát, kterému rozumí ten, kdo ho psal — pravidlo o fixtures z `CLAUDE.md`.
///
/// Nejcennější tvrzení jsou tady dvě negativní: **z cizího textu se nevyrobí jméno atributu**
/// (`nil`, ne půlka řádku) a **prázdný úsek nedá žádný řádek** — jinak by se soubor plnil větami
/// o grafu i nad aplikací, ve které se nic nedělo.
@Suite("Rozbor zásobníku AttributeGraphu (#361)")
struct GraphStackDigestTests {
    @Test("Vrchol, kořen a změněné vstupy ze skutečného výpisu")
    func parsesRealOutput() throws {
        let stack = Policy.graphStack(from: try Fixture.text("attributegraph/stack-text.txt"))
        // `#0` je to, co se počítalo ve chvíli vzorku.
        #expect(stack.top == "StaticBody<ViewBodyAccessor<ProbeRow>, MainThreadFlags>")
        // Poslední rámec je ten, kdo si o celou tu řadu řekl.
        #expect(stack.root == "HostPreferencesTransform<ContentScrollViewPreferenceKey>")
        // Vstup s příznakem `changed` je jediný kandidát na „co ten atribut špiní“, který
        // v zásobníku je — a bere se **typ `self`**, ne typ hodnoty.
        #expect(stack.changed == ["ForEachChild<Range<Int>, Int, ProbeRow>"])
    }

    /// Kdyby se formát změnil (je privátní), má rozbor **zmlknout**, ne vydat nesmysl.
    @Test("Z textu, který takhle nevypadá, nevznikne jméno atributu")
    func ignoresForeignText() {
        let stack = Policy.graphStack(from: "něco úplně jiného\n  #0: bez šipky\n    taky nic\n")
        #expect(stack.top == nil)
        #expect(stack.root == nil)
        #expect(stack.changed.isEmpty)
    }

    @Test("Prázdný úsek nedá ani jeden řádek")
    func silentSliceWritesNothing() {
        #expect(Policy.graphDiagnosticLines(sites: [:], stacks: [], samples: 0).isEmpty)
    }

    /// Počty háků se řadí podle počtu, protože se hledá to, co se opakuje nejčastěji; při shodě
    /// podle jména, ať jsou dva soubory srovnatelné.
    @Test("Počty háků se řadí podle počtu, při shodě podle jména")
    func sitesSortedByCount() {
        let lines = Policy.graphDiagnosticLines(
            sites: ["DiffRow.id": 12, "FileDiff.id": 40, "DiffLine.geometry": 12],
            stacks: [],
            samples: 0
        )
        #expect(lines == ["    graf: FileDiff.id=40 DiffLine.geometry=12 DiffRow.id=12"])
    }

    /// Souhrn je **histogram přes vzorky**, ne poslední vzorek: právě z opakování se pozná, jestli
    /// se kořen kola drží, nebo se jen zachytil náhodný bod.
    @Test("Souhrn sečte kořeny, vrcholy a změněné vstupy přes všechny vzorky")
    func digestCountsAcrossSamples() throws {
        let real = try Fixture.text("attributegraph/stack-text.txt")
        let lines = Policy.graphDiagnosticLines(
            sites: ["DiffRow.id": 3],
            stacks: [real, real],
            samples: 2
        )
        #expect(lines.count > 3)
        #expect(lines[0] == "    graf: DiffRow.id=3")
        #expect(lines[1].hasPrefix("    zásobník: 2 dotazů, 2 vzorků"))
        #expect(lines[1].contains(
            "kořen HostPreferencesTransform<ContentScrollViewPreferenceKey>=2"
        ))
        #expect(lines[1].contains("změněné vstupy ForEachChild<Range<Int>, Int, ProbeRow>=2"))
        // Celý výpis jen z **prvního** vzorku, jinak by v souboru byly stovky řádků za sekundu.
        #expect(lines[2] == "    #0: 11872 StaticBody<ViewBodyAccessor<ProbeRow>, MainThreadFlags>"
            + " -> ModifiedContent<HStack<TupleView<(Text, Spacer)>>, _FrameLayout>")
        #expect(lines.filter { $0.hasPrefix("    #0:") }.count == 1)
        // A ten atribut, o kterém #361 celou dobu je, musí být v záznamu jmenovitě vidět.
        #expect(lines.contains { $0.contains("LazySubviewPlacements<LazyVStackLayout>") })
    }

    /// **Do souboru jdou rámce a změněné vstupy, nic dalšího** — a je to mez, ne estetika: jeden
    /// řádek vstupu měl nad skutečným diffem 1,5 kB a blok jich měl desítky, takže by hořící okno
    /// vyčerpalo strop záznamu za pár minut.
    @Test("Výpis nese rámce a změněné vstupy, ostatní vstupy ne")
    func detailKeepsFramesAndChanges() throws {
        let lines = Policy.graphDiagnosticLines(
            sites: [:],
            stacks: [try Fixture.text("attributegraph/stack-text.txt")],
            samples: 1
        )
        let detail = lines.dropFirst()
        #expect(detail.filter { $0.contains("#") }.count == 12)
        #expect(detail.contains { $0.hasSuffix(", changed") })
        // `-- inputs:` ani vstup bez příznaku se nepřepisují.
        #expect(!detail.contains { $0.contains("-- inputs:") })
    }

    /// Jména typů v grafu jsou generická jména celého podstromu; nejdelší naměřené mělo 1,5 kB.
    /// Řádek se proto zkrátí — jinak by z jednoho vzorku byl kilobajtový záznam.
    @Test("Dlouhé jméno typu se v řádku zkrátí")
    func longTypeNamesAreShortened() throws {
        let long = "  #0: 1 Lazy" + String(repeating: "X", count: 4000) + " -> Value"
        let lines = Policy.graphDiagnosticLines(sites: [:], stacks: [long], samples: 1)
        let summary = try #require(lines.first)
        // Souhrn nese **tři** histogramy (kořen, vrchol, změněné vstupy), takže je stropem
        // trojnásobek — rozhodující je, že neroste s délkou jména typu.
        #expect(summary.count < Policy.graphLineLimit * 3 + 100)
        #expect(summary.contains("…"))
        #expect(try #require(lines.last).count == Policy.graphLineLimit + 5)
    }

    /// Dotaz, ze kterého nic nepřišlo, se **hlásí** — je to rozdíl mezi „graf nic nepočítal“
    /// a „nikdo se neptal“.
    @Test("Dotazy bez vzorku se v řádku přiznají")
    func reportsEmptyAttempts() {
        let lines = Policy.graphDiagnosticLines(sites: ["DiffRow.id": 1], stacks: [], samples: 8)
        #expect(lines.last == "    zásobník: 8 dotazů, 0 vzorků")
    }

    @Test("Věta o dostupnosti zásobníku říká, že řádky nebudou")
    func graphAvailabilityLine() {
        let moment = Date(timeIntervalSince1970: 1_755_600_000)
        #expect(Policy.diagnosticGraphLine(at: moment, in: .gmt, available: true)
            == "2025-08-19T10:40:00Z evaluační zásobník AttributeGraphu k dispozici")
        #expect(Policy.diagnosticGraphLine(at: moment, in: .gmt, available: false).contains(
            "NEJDE otevřít — řádky „zásobník“ v záznamu nebudou"
        ))
    }
}
