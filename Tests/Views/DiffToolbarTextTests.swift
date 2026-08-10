import Testing

@testable import PRism

/// Texty v liště nad diffem a v hlavičce souboru (#219) — obojí čistá funkce, takže se dá
/// vyčerpat výčtem bez kreslení.
@Suite("Sazba lišty diffu")
struct DiffToolbarTextTests {
    private func navigation(position: Int?, total: Int) -> FindingNavigation {
        FindingNavigation(
            position: position,
            total: total,
            hasPrevious: false,
            hasNext: false,
            isComplete: false,
            withoutPlace: 0
        )
    }

    // MARK: - Počitadlo nálezů

    @Test("Po skoku je to `1 z 3 nálezů` a pozice je zvlášť, protože je tučně")
    func counterAfterJump() {
        let counter = FindingNavigationView.counter(navigation(position: 1, total: 3))
        #expect(counter.position == "1")
        #expect(counter.rest == " z 3 nálezů")
    }

    /// Za předložkou `z` je druhý pád, takže u jednoho místa `nálezu`, ne `nález`.
    @Test("Jediné místo skloňuje `z 1 nálezu`")
    func counterSinglePlace() {
        let counter = FindingNavigationView.counter(navigation(position: 1, total: 1))
        #expect(counter.position == "1")
        #expect(counter.rest == " z 1 nálezu")
    }

    /// **Ne `0 z 3`** — nula by tvrdila, že stojím na nultém nálezu, kdežto pravda je, že nikde
    /// nestojím. Samotný počet je první pád, tedy jiná sada tvarů než za předložkou.
    @Test("Před prvním skokem je to jen počet, v prvním pádě")
    func counterBeforeFirstJump() {
        #expect(FindingNavigationView.counter(navigation(position: nil, total: 3)).position == "3")
        #expect(FindingNavigationView.counter(navigation(position: nil, total: 3)).rest == " nálezy")
        #expect(FindingNavigationView.counter(navigation(position: nil, total: 1)).rest == " nález")
        #expect(FindingNavigationView.counter(navigation(position: nil, total: 7)).rest == " nálezů")
    }

    // MARK: - Cesta v hlavičce souboru

    @Test("Cesta se dělí na složku a jméno, lomítko zůstává u složky")
    func pathSplit() {
        let parts = FilePathText.parts(of: "src/Vault/SecretClient.php")
        #expect(parts.directory == "src/Vault/")
        #expect(parts.name == "SecretClient.php")
    }

    /// Soubor v kořeni repa je celý jméno — prázdná složka se pak nekreslí vůbec.
    @Test("Soubor bez složky je celý jméno")
    func pathWithoutDirectory() {
        let parts = FilePathText.parts(of: "Cart.php")
        #expect(parts.directory.isEmpty)
        #expect(parts.name == "Cart.php")
    }

    /// Cesta končící lomítkem v diffu nevzniká, ale typ ji nezakazuje — a prázdné jméno by
    /// hlavičku nechalo bez popisku, tedy bez toho jediného, co se z ní čte.
    @Test("Cesta končící lomítkem nezůstane bez jména")
    func pathEndingWithSlash() {
        let parts = FilePathText.parts(of: "src/Vault/")
        #expect(parts.directory.isEmpty)
        #expect(parts.name == "src/Vault/")
    }

    // MARK: - Kapsle s nálezy v hlavičce

    /// **Blokující má vlastní slovo, ne jen barvu** — kapsle je tvarem k nerozeznání od odznaku
    /// změny vedle ní, takže barva sama by byla jediný rozdíl.
    @Test("Blokující nález se v kapsli jmenuje, ne jen obarví")
    func badgeNamesBlocking() {
        let badge = DiffFileHeaderView.badgeLabel(blocking: 1, total: 1)
        #expect(badge?.label == "1 blokuje")
        #expect(badge?.isBlocking == true)
    }

    /// Sloveso se skloňuje: „2 blokuje“ i „5 blokují“ jsou špatně česky.
    @Test("Sloveso v kapsli se skloňuje")
    func badgeDeclinesTheVerb() {
        #expect(DiffFileHeaderView.badgeLabel(blocking: 2, total: 3)?.label == "2 blokují")
        #expect(DiffFileHeaderView.badgeLabel(blocking: 5, total: 5)?.label == "5 blokuje")
    }

    /// Bez blokujícího se počítají místa, ne blokující — a v prvním pádě.
    @Test("Neblokující nález se počítá jako nález")
    func badgeCountsPlainFindings() {
        let badge = DiffFileHeaderView.badgeLabel(blocking: 0, total: 1)
        #expect(badge?.label == "1 nález")
        #expect(badge?.isBlocking == false)
        #expect(DiffFileHeaderView.badgeLabel(blocking: 0, total: 3)?.label == "3 nálezy")
    }

    /// Prázdná kapsle se nekreslí — soubor, ve kterém není co vyřídit, nemá mít odznak.
    @Test("Bez nálezů kapsle není")
    func badgeIsAbsentWithoutFindings() {
        #expect(DiffFileHeaderView.badgeLabel(blocking: 0, total: 0) == nil)
    }
}
