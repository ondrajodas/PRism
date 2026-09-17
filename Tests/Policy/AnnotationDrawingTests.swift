import Foundation
import Testing

@testable import PRism

/// Co se z anotací **kreslí** (#525) — popisky druhů, přepínač vět a údaj ve stavovém řádku.
///
/// Dvě věci se tady rozbijí potichu, takže jsou tvrzené zvlášť: **vypnutý přepínač nevydá ani
/// jednu anotaci** (tedy seznam řádků diffu se složí přesně jako bez nich) a **pilulka druhu se
/// přepínačem neřídí**, protože ta schovává jedno slovo v hlavičce, ne řádek nad kódem.
@Suite("Kresba anotací v diffu (#525)")
struct AnnotationDrawingTests {
    private let pr = PRIdentifier(repo: RepoID(owner: "cli", name: "cli"), number: 42)

    private func stored(
        headSha: String = "4f2ac9137bd8",
        hunks: [HunkAnnotation] = [],
        files: [FileAnnotation] = []
    ) -> StoredAnnotations {
        StoredAnnotations(
            pullRequest: pr,
            headSha: headSha,
            hunks: hunks,
            files: files,
            outcome: .finished,
            sessionID: "s1",
            answered: true,
            dropped: 0,
            finishedAt: Date(timeIntervalSince1970: 100),
            usage: nil
        )
    }

    private func file(_ path: String = "src/Vault/SecretClient.php", hunks count: Int = 2) -> FileDiff {
        FileDiff(
            oldPath: path,
            newPath: path,
            change: .modified,
            isBinary: false,
            hunks: (0..<count).map {
                DiffHunk(oldStart: $0 * 10 + 1, oldCount: 3, newStart: $0 * 10 + 1, newCount: 3, heading: "", lines: [])
            }
        )
    }

    private func annotation(
        _ file: String = "src/Vault/SecretClient.php",
        hunk: Int = 1,
        why: String = "Zavádí cache před voláním vaultu.",
        source: String? = "z commitu perf: cache secrets"
    ) -> HunkAnnotation {
        HunkAnnotation(file: file, hunk: hunk, why: why, source: source)
    }

    // MARK: - Popisky druhů změny

    /// **Vyčerpávající výčet**: nový druh nesmí projít bez českého popisku. Do #525 popisky
    /// neexistovaly schválně (nikde se nekreslily), takže je tenhle test to jediné, co drží
    /// `rawValue` v angličtině a text v okně česky.
    @Test("Každý druh změny má popisek", arguments: FileChangeKind.allCases)
    func everyKindHasALabel(kind: FileChangeKind) {
        #expect(!Policy.changeKindChip(of: kind).label.isEmpty)
    }

    /// Popisky se **nesmí opakovat**: dvě kapsle se stejným slovem znamenají, že z hlavičky nejde
    /// poznat, co session o souboru řekla. (`test` je shodou okolností týž řetězec jako `rawValue`
    /// a je to v pořádku — česky se to tak jmenuje.)
    @Test("Popisky druhů se neopakují")
    func theLabelsAreDistinct() {
        let labels = FileChangeKind.allCases.map { Policy.changeKindChip(of: $0).label }
        #expect(Set(labels).count == labels.count)
    }

    @Test("Popisky druhů jsou ze zákresu doslova")
    func theLabelsComeFromTheDrawing() {
        let labels = FileChangeKind.allCases.map { Policy.changeKindChip(of: $0).label }
        #expect(labels == ["změna chování", "refaktor", "test", "konfigurace", "generované"])
    }

    /// **Akcent má jedině `změna chování`.** Ostatní čtyři jsou tvrzení session o souboru, který
    /// se čte později — kdyby svítily taky, nebyl by v hlavičce rozdíl mezi „koukni napřed“ a
    /// „tohle je lock“.
    @Test("Akcentem svítí jedině změna chování", arguments: FileChangeKind.allCases)
    func onlyBehaviourIsProminent(kind: FileChangeKind) {
        #expect(Policy.changeKindChip(of: kind).isProminent == (kind == .behaviour))
    }

    // MARK: - Přepínač vět

    /// **Vypnuto = prázdná mapa.** Je to tvrzení o tom, že se něco **nenakreslí**, tedy ta
    /// cennější polovina: schovaný řádek by po sobě nechal mezeru a vypnutý přepínač by se dal
    /// poznat jen tím, že text zmizel.
    @Test("Vypnutý přepínač nevydá ani jednu anotaci")
    func theToggleOffYieldsNothing() {
        let record = stored(hunks: [annotation(hunk: 1), annotation(hunk: 2)])
        #expect(Policy.hunkAnnotations(of: record, in: file(), isOn: false).isEmpty)
    }

    /// Zapnutý přepínač nepřidává ani neubírá nic proti párování z #524 — je to **tatáž** mapa.
    @Test("Zapnutý přepínač vydá totéž co párování")
    func theToggleOnYieldsThePairing() {
        let record = stored(hunks: [annotation(hunk: 1), annotation(hunk: 2)])
        let file = file()
        #expect(
            Policy.hunkAnnotations(of: record, in: file, isOn: true)
                == Policy.annotations(of: record, in: file)
        )
    }

    /// **Zastaralé anotace se nekreslí, ani se zapnutým přepínačem** (tvrdá podmínka č. 5).
    /// Cesta do diffu vede přes `annotations(of:head:)`, takže se tvrdí celá, ne jen její konec.
    @Test("Anotace z jiné hlavy se nenakreslí ani zapnuté")
    func staleAnnotationsAreNeverDrawn() {
        let record = stored(headSha: "aaaa1111", hunks: [annotation(hunk: 1)])
        let valid = Policy.annotations(of: record, head: "bbbb2222")

        #expect(valid == nil)
        #expect(Policy.hunkAnnotations(of: valid, in: file(), isOn: true).isEmpty)
    }

    /// **Pilulka druhu se přepínačem neřídí.** Přepínač je o řádcích nad hunky; druh je jedno
    /// slovo v hlavičce, která tam stojí tak jako tak.
    @Test("Druh změny přepínač vět neschová")
    func theKindIgnoresTheToggle() {
        let record = stored(
            hunks: [annotation(hunk: 1)],
            files: [FileAnnotation(file: "src/Vault/SecretClient.php", kind: .behaviour)]
        )
        #expect(Policy.hunkAnnotations(of: record, in: file(), isOn: false).isEmpty)
        #expect(Policy.changeKind(of: record, in: file()) == .behaviour)
    }

    /// Záznam **jen** s druhy změny přepínač do nabídky nedostane — nebylo by co schovat.
    @Test("Přepínač se nabízí jedině tam, kde jsou věty")
    func theToggleAppearsOnlyWithSentences() {
        #expect(stored(hunks: [annotation()]).hasHunkAnnotations)
        #expect(
            !stored(files: [FileAnnotation(file: "composer.lock", kind: .generated)])
                .hasHunkAnnotations
        )
    }

    // MARK: - Stavový řádek

    @Test("Stavový řádek vypíše počet vět a hlavu")
    func theStatusNamesTheCountAndTheHead() {
        let record = stored(hunks: (1...4).map { annotation(hunk: $0) })
        #expect(Policy.annotationStatus(of: record) == "Anotace · 4 věty · proti 4f2ac91")
    }

    /// Čeština se skloňuje — `1 věty` je špatně a `5 věty` taky.
    @Test(
        "Počet vět se skloňuje",
        arguments: [(1, "1 věta"), (2, "2 věty"), (4, "4 věty"), (5, "5 vět"), (12, "12 vět")]
    )
    func theCountIsDeclined(count: Int, text: String) throws {
        let record = stored(hunks: (1...count).map { annotation(hunk: $0) })
        let status = try #require(Policy.annotationStatus(of: record))
        #expect(status.contains(text))
    }

    /// **Záznam bez jediné věty se nepíše.** `Anotace · 0 vět` by v pruhu tvrdilo, že je co číst;
    /// že session doběhla a nic nenapsala, patří do dráhy `anotace` v tabu `Průběh`.
    @Test("Bez vět se ve stavovém řádku nepíše nic")
    func noSentencesMeansNoStatus() {
        #expect(Policy.annotationStatus(of: nil) == nil)
        #expect(Policy.annotationStatus(of: stored()) == nil)
        #expect(
            Policy.annotationStatus(
                of: stored(files: [FileAnnotation(file: "composer.lock", kind: .generated)])
            ) == nil
        )
    }

    /// Hlava se zkracuje na sedm znaků, jako všude jinde v okně — a **krátká se nedoplňuje**.
    @Test("Hlava se vypisuje zkrácená")
    func theHeadIsShortened() throws {
        let long = try #require(Policy.annotationStatus(of: stored(
            headSha: "4f2ac9137bd8aa0011",
            hunks: [annotation()]
        )))
        #expect(long.hasSuffix("proti 4f2ac91"))
        let short = try #require(Policy.annotationStatus(of: stored(
            headSha: "4f2ac",
            hunks: [annotation()]
        )))
        #expect(short.hasSuffix("proti 4f2ac"))
    }

    /// Prázdná hlava je „nevím“, ne hodnota — a `proti ` s prázdnem by tvrdilo, že se ví, proti
    /// čemu to platí. Do diffu se takový záznam nedostane (`annotations(of:head:)`), pruh si to
    /// hlídá sám.
    @Test("Prázdná hlava údaj nevydá")
    func anEmptyHeadYieldsNothing() {
        #expect(Policy.annotationStatus(of: stored(headSha: "", hunks: [annotation()])) == nil)
    }

    // MARK: - Odečítač obrazovky

    /// Zdroj se **nevynechává**: je to doklad, ze kterého se pozná, jestli věta stojí na commitu,
    /// nebo na dohadu.
    @Test("Věta pro odečítač nese i zdroj")
    func theSpeechCarriesTheSource() {
        #expect(
            Policy.annotationSpeech(of: annotation(why: "Cachuje klíč.", source: "z commitu perf"))
                == "Cachuje klíč. — z commitu perf"
        )
    }

    @Test("Bez zdroje zbude samotná věta", arguments: [nil, ""])
    func withoutASourceOnlyTheSentenceRemains(source: String?) {
        #expect(
            Policy.annotationSpeech(of: annotation(why: "Cachuje klíč.", source: source))
                == "Cachuje klíč."
        )
    }
}
