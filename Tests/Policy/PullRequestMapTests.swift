import Foundation
import Testing

@testable import PRism

/// Mapa PR — pás pod hlavičkou (#501).
///
/// Čtyři věci, které se tu dají pokazit **potichu**, tedy tak, že pás pořád vypadá jako pás:
///
/// - **zahodit logaritmus.** Lineární šířka dá u PR s lockem obrázek, ze kterého se nic nedozví —
///   a přitom je to pořád pás se sedmi segmenty. Míří na to test s **vloženou regresí**;
/// - **přerůst dostupnou šířku.** Minimum tři body na segment se musí odečíst z dělení, jinak se
///   součet u PR s jedním velkým souborem a šesti drobnostmi vejde do pásu jen náhodou;
/// - **splést závažnost s druhem souboru.** Nový soubor s blokujícím nálezem má být červený;
///   kdyby o barvě rozhodovalo `isNew` dřív, byl by zelený a v pásu by to nešlo poznat;
/// - **spočítat něco jiného, než co je vidět.** Popisek `5 nálezů` musí sedět se součtem segmentů,
///   protože je to jediné číslo, proti kterému se pás dá zkontrolovat očima.
@Suite("Mapa PR (#501)")
struct PullRequestMapTests {
    // MARK: - Šířky

    /// **Rozložení ze sekce 03 návrhu**, jak ho změřil deck *Směry pro PRism*: sedm souborů PR
    /// `keboola/vault#85`, ve kterých `composer.lock` mění 2 790 řádků z 2 952. Tři z nich mají
    /// počty vypsané i v mockupu (`+18 −6`, `+31 −12`, `+64 −0`).
    private let realistic: [(path: String, lines: Int)] = [
        ("src/Vault/SecretClient.php", 24),
        ("src/Vault/Encryptor.php", 43),
        ("src/Vault/SecretNotFound.php", 21),
        ("tests/SecretClientTest.php", 64),
        ("composer.json", 4),
        ("composer.lock", 2790),
        ("phpunit.xml.dist", 6),
    ]

    /// **Hlavní tvrzení tohohle issue.** Nad tím rozložením vezme lock **s logaritmem 30,8 %**
    /// pásu; lineárně by to bylo 94,5 % a ze zbytku šest čárek.
    ///
    /// Tolerance je desetina procenta, ne rovnost — hodnota je z `log2`, tedy z pohyblivé řádové
    /// tečky, a test má chytat **jinou váhovou funkci**, ne poslední bit.
    @Test("Lock vezme logaritmem 31 % pásu, ne 94 %")
    func theLockTakesAThirdOfTheStripNotAllOfIt() {
        let map = Policy.pullRequestMap(files: realistic.map(file(_:)))
        let widths = Policy.mapWidths(of: map.segments, in: 1000)
        let available = 1000 - 2 * Double(map.segments.count - 1)

        #expect(widths.count == 7)
        let lock = widths[5]
        #expect(abs(lock / available - 0.308) < 0.001, "lock má \(lock / available * 100) % pásu")

        // A druhá strana téhož: **lineární** podíl je ta zamítnutá varianta, a čísla se rozcházejí
        // trojnásobně. Kdyby se váha přepsala na `Double(changedLines)`, spadne tvrzení výš.
        let linear = 2790.0 / 2952.0
        #expect(abs(linear - 0.945) < 0.001, "lineárně by lock vzal \(linear * 100) %")
    }

    /// **Vložená regrese**: s lineární váhou by lock vzal víc než 90 % pásu a test o 64 řádcích by
    /// spadl na minimum. Tvrdí se to na **týchž datech**, jen s vlastním výpočtem podílu — kdyby
    /// se v `Policy` logaritmus jednou zahodil, tenhle test ukáže, o kolik se pás zhorší.
    @Test("Bez logaritmu by lock vzal přes 90 % a test spadl na minimum")
    func theLinearWidthWouldSwallowTheStrip() {
        let map = Policy.pullRequestMap(files: realistic.map(file(_:)))
        let total = Double(realistic.reduce(0) { $0 + $1.lines })
        let available = 1000 - 2 * Double(map.segments.count - 1)

        let linear = map.segments.map { Double($0.changedLines) / total * available }
        #expect(linear[5] / available > 0.9)
        // Test o 64 řádcích: lineárně 21 bodů, logaritmem 175 — tedy rozdíl mezi „čárka“
        // a „segment, na který se dá kliknout“.
        let logarithmic = Policy.mapWidths(of: map.segments, in: 1000)
        #expect(linear[3] < 25)
        #expect(logarithmic[3] > 150)
    }

    /// **Součet je přesně dostupná šířka** — pás jde od hrany k hraně. Přes pásmo šířek, ne na
    /// jedné: přepočet po vytlačení minim je zrovna to místo, kde se dá zbytek ztratit.
    @Test("Součet šířek je přesně dostupná šířka")
    func theWidthsAddUpToTheStrip() {
        for total in [200.0, 400, 640, 1000, 1600] {
            let map = Policy.pullRequestMap(files: realistic.map(file(_:)))
            let widths = Policy.mapWidths(of: map.segments, in: total)
            let available = total - 2 * Double(map.segments.count - 1)
            #expect(abs(widths.reduce(0, +) - available) < 0.001,
                    "v \(total) b vyšel součet \(widths.reduce(0, +)) místo \(available)")
        }
    }

    /// **Nejmíň tři body na segment.** Jedno velké a šest malých je právě ten případ, kvůli
    /// kterému logaritmus existuje — a zároveň ten, ve kterém by podíl bez minima vydal segmenty
    /// pod bod.
    @Test("Žádný segment není užší než tři body")
    func noSegmentFallsBelowTheMinimum() {
        let files = [("big.lock", 40_000)] + (1...6).map { ("f\($0).php", 1) }
        let map = Policy.pullRequestMap(files: files.map(file(_:)))

        for total in [120.0, 300, 900] {
            let widths = Policy.mapWidths(of: map.segments, in: total)
            #expect(widths.allSatisfy { $0 >= 3 - 0.001 }, "v \(total) b vyšlo \(widths)")
            let available = total - 2 * Double(map.segments.count - 1)
            #expect(abs(widths.reduce(0, +) - available) < 0.001)
        }
    }

    /// **A když se ani minima nevejdou, dělí se rovným dílem** — segment se nezahodí nikdy.
    /// Padesát souborů v úzkém okně: 50 × 3 + 49 × 2 = 248 bodů, tedy víc, než co pás v tabu
    /// o 300 bodech (třetina okna 700) unese.
    @Test("Když se minima nevejdou, dělí se rovným dílem")
    func fallsBackToEqualSharesWhenEvenTheMinimumDoesNotFit() {
        let map = Policy.pullRequestMap(files: (1...50).map { file(("f\($0).php", $0 * 7)) })
        let widths = Policy.mapWidths(of: map.segments, in: 140)

        #expect(widths.count == 50)
        #expect(Set(widths.map { ($0 * 1000).rounded() }).count == 1, "díly se nerozdělily rovně")
        #expect(widths.allSatisfy { $0 > 0 }, "segment se zahodil: \(widths)")
    }

    /// Binárka nemění řádky, takže má váhu nula — a **dostane minimum, ne nulu**: soubor v PR je
    /// a v pásu má být vidět. Samé binárky se dělí rovným dílem, ne `NaN`em.
    @Test("Binárky mají váhu nula a dělí se rovným dílem")
    func binariesShareTheStripEvenly() {
        let map = Policy.pullRequestMap(files: (1...4).map { file(("obr\($0).png", 0)) })
        let widths = Policy.mapWidths(of: map.segments, in: 400)

        #expect(widths.allSatisfy { $0.isFinite && $0 > 3 }, "\(widths)")
        #expect(Set(widths.map { ($0 * 1000).rounded() }).count == 1)
    }

    @Test("Prázdný pás nemá segmenty ani šířky")
    func anEmptyDiffHasNoStrip() {
        let map = Policy.pullRequestMap(files: [])
        #expect(map.isEmpty)
        #expect(Policy.mapWidths(of: map.segments, in: 500).isEmpty)
        #expect(map.summary == "0 souborů")
    }

    /// Nulová i záporná šířka je **odpověď, ne pád**: pás se v prvním průchodu rozvržení může
    /// ptát na cokoli.
    @Test("Bez místa vyjdou nulové šířky")
    func noRoomMeansZeroWidths() {
        let map = Policy.pullRequestMap(files: realistic.map(file(_:)))
        for total in [0.0, -10, 8] {
            let widths = Policy.mapWidths(of: map.segments, in: total)
            #expect(widths.count == map.segments.count)
            #expect(widths.allSatisfy { $0 >= 0 && $0.isFinite }, "v \(total) b vyšlo \(widths)")
        }
    }

    // MARK: - Barva podle nejhoršího nálezu

    @Test("Segment bez nálezu nemá značku")
    func aCleanFileHasNoMarker() {
        let map = Policy.pullRequestMap(files: [file(("src/A.php", 10))])
        #expect(map.segments[0].marker == nil)
        #expect(map.segments[0].isNew == false)
    }

    @Test("Obyčejný nález dá značku nálezu")
    func aPlainFindingMarksTheSegment() {
        let map = map(findings: [makeFinding(file: "src/A.php", line: 3, category: "style")])
        #expect(map.segments[0].marker == .findings)
        #expect(map.segments[0].findings == 1)
    }

    /// **Nejcennější tvrzení téhle části, a v obou pořadích**: blokující přebíjí obyčejný a
    /// nedá se přebít zpátky.
    @Test("Blokující nález přebije obyčejný bez ohledu na pořadí")
    func blockingWinsRegardlessOfOrder() {
        let plain = makeFinding(file: "src/A.php", line: 3, category: "style")
        let blocking = makeFinding(file: "src/A.php", line: 9, category: "correctness")

        for findings in [[plain, blocking], [blocking, plain]] {
            let map = map(findings: findings)
            #expect(map.segments[0].marker == .blocking, "pořadí rozhodlo o barvě")
            #expect(map.segments[0].findings == 2, "místa se počítají po skupinách")
        }
    }

    /// **Barva je závažnost, ne druh souboru**: nový soubor s blokujícím nálezem nese `blocking`,
    /// takže si ho kresba obarví červeně, ne zeleně.
    @Test("Nový soubor s blokujícím nálezem zůstává blokující")
    func aNewFileWithABlockingFindingStaysBlocking() {
        let files = [FileDiff(oldPath: nil, newPath: "src/New.php", change: .added,
                              isBinary: false, hunks: [hunk(lines: 12)], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(
            files: files,
            findings: Policy.groups(of: [makeFinding(file: "src/New.php", line: 3, category: "security")])
        )

        #expect(map.segments[0].isNew)
        #expect(map.segments[0].marker == .blocking)
    }

    /// Nález, který **kategorii nemá v blokující sadě**, značku dostane, ale ne blokující —
    /// a sada je parametr, takže se to musí řídit tím, co je v konfiguraci.
    @Test("Blokující sada rozhoduje o barvě")
    func theBlockingCategoriesDecide() {
        let findings = Policy.groups(of: [makeFinding(file: "src/A.php", line: 3, category: "style")])
        let files = [file(("src/A.php", 10))]

        #expect(Policy.pullRequestMap(files: files, findings: findings).segments[0].marker == .findings)
        #expect(
            Policy.pullRequestMap(files: files, findings: findings, categories: ["style"])
                .segments[0].marker == .blocking
        )
    }

    /// **Přejmenovaný soubor se hledá po obou cestách.** Reviewer umí nález nahlásit pod tou
    /// starou, kdežto pás kreslí `displayPath` — bez toho by přejmenovaný soubor vyšel jako
    /// neutrální a nikdo by si toho nevšiml.
    @Test("Nález pod starou cestou přejmenovaného souboru se najde")
    func aFindingUnderTheOldPathCountsToo() {
        let files = [FileDiff(oldPath: "src/Old.php", newPath: "src/New.php", change: .renamed,
                              isBinary: false, hunks: [hunk(lines: 8)], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(
            files: files,
            findings: Policy.groups(of: [makeFinding(file: "src/Old.php", line: 2, category: "correctness")])
        )

        #expect(map.segments[0].path == "src/New.php")
        #expect(map.segments[0].marker == .blocking)
    }

    /// **Odmítnutý nález značku nedá** (#113). Filtruje ho `FindingGroup.activeFindings`, tedy
    /// tatáž cesta, jakou to dělá strom a kapsle v hlavičce souboru.
    @Test("Odmítnutý nález se do pásu nepočítá")
    func aDismissedFindingLeavesNoMarker() {
        let finding = makeFinding(file: "src/A.php", line: 3, category: "correctness")
        let map = Policy.pullRequestMap(
            files: [file(("src/A.php", 10))],
            findings: Policy.groups(of: [finding], dismissals: makeDismissals([finding]))
        )

        #expect(map.segments[0].marker == nil)
        #expect(map.segments[0].findings == 0)
        #expect(map.summary == "1 soubor")
    }

    // MARK: - Tlumení prošlých

    @Test("Prošlý soubor se tlumí, změněný od prošlého ne")
    func onlyReadFilesAreDimmed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let map = Policy.pullRequestMap(
            files: [file(("src/A.php", 10)), file(("src/B.php", 10)), file(("src/C.php", 10))],
            readStates: [
                "src/A.php": .read(at: now),
                "src/B.php": .changed(readAt: now),
            ]
        )

        #expect(map.segments[0].readState.isRead)
        #expect(map.segments[1].readState.isRead == false, "`changed` je práce, která se vrátila")
        #expect(map.segments[2].readState == .unread)
        #expect(map.summary == "3 soubory · 1 prošlý")
    }

    /// Značka souboru, který v diffu **není**, se do pásu nedostane — pás popisuje diff.
    @Test("Značka mimo diff se do pásu nedostane")
    func marksOutsideTheDiffAreIgnored() {
        let map = Policy.pullRequestMap(
            files: [file(("src/A.php", 10))],
            readStates: ["src/Zmizel.php": .read(at: Date(timeIntervalSince1970: 1))]
        )
        #expect(map.segments[0].readState == .unread)
        #expect(map.summary == "1 soubor")
    }

    // MARK: - Vlákna

    /// Vlákno je čárka na podílu své polohy. Hunk má 10 řádků, vlákno na pátém → **4/9**.
    @Test("Vlákno leží na podílu svého řádku")
    func aThreadSitsAtItsShareOfTheFile() {
        let files = [FileDiff(oldPath: "src/A.php", newPath: "src/A.php", change: .modified,
                              isBinary: false, hunks: [spanningHunk(rows: 10)], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(files: files, threads: [thread(path: "src/A.php", line: 5)])

        #expect(map.segments[0].threads.count == 1)
        #expect(abs(map.segments[0].threads[0] - 4.0 / 9.0) < 0.001,
                "vyšlo \(map.segments[0].threads)")
        #expect(map.summary == "1 soubor · 1 vlákno")
    }

    /// Vlákno, jehož řádek v diffu **není**, čárku nedostane — jinak by pás tvrdil, že je v tom
    /// souboru diskuze, kterou nejde najít.
    @Test("Vlákno mimo hunky čárku nedostane")
    func aThreadOutsideTheHunksGetsNoTick() {
        let files = [FileDiff(oldPath: "src/A.php", newPath: "src/A.php", change: .modified,
                              isBinary: false, hunks: [spanningHunk(rows: 10)], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(files: files, threads: [thread(path: "src/A.php", line: 900)])

        #expect(map.segments[0].threads.isEmpty)
        #expect(map.summary == "1 soubor")
    }

    /// Soubor o jednom řádku: podíl je `0,5`, ne `NaN` ani dělení nulou.
    @Test("Soubor o jednom řádku dá čárku doprostřed")
    func aSingleLineFilePutsTheTickInTheMiddle() {
        let files = [FileDiff(oldPath: "src/A.php", newPath: "src/A.php", change: .modified,
                              isBinary: false, hunks: [spanningHunk(rows: 1)], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(files: files, threads: [thread(path: "src/A.php", line: 1)])

        #expect(map.segments[0].threads == [0.5])
    }

    /// **Oprava po Copilotovi na PR #539, a je to tvrzení o tom, že se něco NEstalo.** První
    /// podoba `threadSpots` vracela `0,5` pro každé vlákno, jakmile měl soubor nejvýš jeden řádek
    /// — tedy **bez** kontroly `matches`. Pás by pak tvrdil diskuzi v souboru, ve kterém pro ni
    /// není řádek. Test výš (`Vlákno mimo hunky čárku nedostane`) to nechytal: běžel nad
    /// desetiřádkovým hunkem, tedy tou větví, kde se `matches` volalo.
    @Test("Vlákno mimo jediný řádek souboru čárku nedostane")
    func aThreadOffTheOnlyLineGetsNoTick() {
        let files = [FileDiff(oldPath: "src/A.php", newPath: "src/A.php", change: .modified,
                              isBinary: false, hunks: [spanningHunk(rows: 1)], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(files: files, threads: [thread(path: "src/A.php", line: 42)])

        #expect(map.segments[0].threads.isEmpty)
        #expect(map.summary == "1 soubor")
    }

    /// A binárka nemá řádky vůbec, takže se u ní nekreslí nic — ani `0,5`.
    @Test("Binárka čárku vlákna nedostane")
    func aBinaryFileGetsNoTick() {
        let files = [FileDiff(oldPath: "obr.png", newPath: "obr.png", change: .modified,
                              isBinary: true, hunks: [], blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(files: files, threads: [thread(path: "obr.png", line: 1)])

        #expect(map.segments[0].threads.isEmpty)
        #expect(map.summary == "1 soubor")
    }

    // MARK: - Popisek a nápověda

    /// Popisek se skládá z toho, co má co říct. Vyčerpávající výčet nul a jedniček — právě tady
    /// se dá napsat `0 nálezů` a nikdo si toho nevšimne.
    @Test("Popisek připojuje jen to, co má co říct", arguments: [
        (7, 3, 5, 2, "7 souborů · 3 prošlé · 5 nálezů · 2 vlákna"),
        (7, 0, 0, 0, "7 souborů"),
        (1, 1, 1, 1, "1 soubor · 1 prošlý · 1 nález · 1 vlákno"),
        (2, 0, 4, 0, "2 soubory · 4 nálezy"),
        (5, 5, 0, 1, "5 souborů · 5 prošlých · 1 vlákno"),
        (0, 0, 0, 0, "0 souborů"),
    ])
    func theSummaryOnlySaysWhatItHas(files: Int, read: Int, findings: Int, threads: Int, expected: String) {
        #expect(Policy.mapSummary(files: files, read: read, findings: findings, threads: threads) == expected)
    }

    /// Nápověda pod kurzorem. **Stav značky je vždycky poslední a vždycky tam je**; nálezy
    /// a vlákna se vynechávají, když žádné nejsou.
    @Test("Nápověda segmentu")
    func theTooltipSaysWhatIsInTheFile() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let files = [FileDiff(oldPath: "src/Vault/Encryptor.php", newPath: "src/Vault/Encryptor.php",
                              change: .modified, isBinary: false, hunks: [spanningHunk(rows: 10)],
                              blobs: "aaa..bbb")]
        let map = Policy.pullRequestMap(
            files: files,
            findings: Policy.groups(of: [makeFinding(file: "src/Vault/Encryptor.php", line: 3)]),
            threads: [thread(path: "src/Vault/Encryptor.php", line: 5)]
        )
        #expect(Policy.mapTooltip(of: map.segments[0])
            == "Encryptor.php · +1 −0 · 1 nález · 1 vlákno · neprošlo")

        let read = Policy.pullRequestMap(files: files, readStates: ["src/Vault/Encryptor.php": .read(at: now)])
        #expect(Policy.mapTooltip(of: read.segments[0]) == "Encryptor.php · +1 −0 · prošlo")

        let changed = Policy.pullRequestMap(
            files: files,
            readStates: ["src/Vault/Encryptor.php": .changed(readAt: now)]
        )
        #expect(Policy.mapTooltip(of: changed.segments[0])
            == "Encryptor.php · +1 −0 · změněno od prošlého")
    }

    @Test("Stav značky se pojmenuje výčtem", arguments: [
        (FileReviewState.unread, "neprošlo"),
        (.read(at: Date(timeIntervalSince1970: 1)), "prošlo"),
        (.changed(readAt: Date(timeIntervalSince1970: 1)), "změněno od prošlého"),
    ])
    func theReadLabelIsExhaustive(state: FileReviewState, expected: String) {
        #expect(Policy.mapReadLabel(of: state) == expected)
    }

    /// Jméno segmentu je **poslední část cesty**, protože do dvacetibodového segmentu se cesta
    /// nevejde. Soubor v kořeni si nechá své jméno celé.
    @Test("Jméno segmentu je poslední část cesty")
    func theSegmentNameIsTheLastPathComponent() {
        let map = Policy.pullRequestMap(files: [
            file(("src/Vault/SecretClient.php", 10)),
            file(("composer.lock", 10)),
        ])
        #expect(map.segments.map(\.name) == ["SecretClient.php", "composer.lock"])
        #expect(map.segments.map(\.path) == ["src/Vault/SecretClient.php", "composer.lock"])
    }

    // MARK: - Popisek v úzké řádce

    /// **Popisek ustupuje první** (#501). Práh je změřený: popisek referenčního rozložení stojí
    /// ~230 bodů, takže se v pohledu vedle sebe (detail 347 b, tedy řádka 315) nekreslí — pásu by
    /// zbylo 73 bodů a v nich jsou z segmentů čárky.
    @Test("Popisek se v úzké řádce nekreslí", arguments: [
        // řádka, popisek, kreslí se
        (Double?.none, 230.0, true),
        (.some(0), 230.0, true),
        (.some(315), 230.0, false),
        (.some(422), 230.0, true),
        (.some(421), 230.0, false),
        (.some(1015), 230.0, true),
        // Kratší popisek (`7 souborů`) se vejde i do úzké řádky.
        (.some(315), 80.0, true),
    ])
    func theSummaryRetreatsFirst(available: Double?, label: Double, expected: Bool) {
        #expect(Policy.mapShowsSummary(available: available, label: label) == expected)
    }

    // MARK: - Obrys podle výřezu

    /// Který segment má obrys — **tatáž odpověď, jakou dostane ukotvená hlavička v diffu**
    /// (`Policy.pinnedFileHeader`). Rozsahy jdou pod sebou bez mezer, jak je měří sekce souboru.
    @Test("Obrys má soubor, který drží horní hranu výřezu", arguments: [
        (0.0, 0), (10.0, 0), (99.9, 0), (100.0, 1), (250.0, 2), (10_000.0, 2),
    ])
    func theOutlineFollowsTheViewport(top: Double, expected: Int) {
        let extents: [ClosedRange<Double>] = [0...100, 100...200, 200...300]
        #expect(Policy.mapCurrentSegment(extents: extents, top: top) == expected)
    }

    /// **Dokud nejsou rozsahy změřené, nesvítí nic.** `DiffFileExtents.ordered(of:)` vrací
    /// prázdno, když chybí i jeden — díra uprostřed by znamenala obrys u cizího souboru.
    @Test("Bez změřených rozsahů se obrys nekreslí")
    func noExtentsMeanNoOutline() {
        #expect(Policy.mapCurrentSegment(extents: [], top: 0) == nil)
        #expect(Policy.mapCurrentSegment(extents: [], top: 500) == nil)
        // A výřez nad prvním souborem (pružné scrollování nad horní hranu) taky ne.
        #expect(Policy.mapCurrentSegment(extents: [100...200], top: -30) == nil)
    }

    // MARK: - Krok po souborech

    /// `⌥←`/`⌥→` **nezacyklují** a bez výchozího bodu nedělají nic.
    @Test("Krok po souborech se zastaví na kraji", arguments: [
        (Int?.some(0), NavigationStep.forward, Int?.some(1)),
        (.some(2), .forward, nil),
        (.some(2), .backward, .some(1)),
        (.some(0), .backward, nil),
        (nil, .forward, nil),
        (nil, .backward, nil),
        (.some(9), .forward, nil),
        (.some(-1), .backward, nil),
    ])
    func steppingStopsAtTheEdges(current: Int?, direction: NavigationStep, expected: Int?) {
        #expect(Policy.mapStep(from: current, direction, count: 3) == expected)
    }

    @Test("Nad prázdným pásem krok nic nevydá")
    func steppingOverAnEmptyStripDoesNothing() {
        #expect(Policy.mapStep(from: 0, .forward, count: 0) == nil)
        #expect(Policy.mapStep(from: nil, .forward, count: 0) == nil)
    }

    // MARK: - Fixtures

    private func map(findings: [Finding]) -> PullRequestMap {
        Policy.pullRequestMap(
            files: [file(("src/A.php", 10))],
            findings: Policy.groups(of: findings)
        )
    }

    /// Soubor o daném počtu změněných řádků. Rozdělení mezi `+` a `−` je 3 : 7 — nesymetrické
    /// schválně, ať se `additions` a `deletions` nedají zaměnit.
    private func file(_ input: (path: String, lines: Int)) -> FileDiff {
        FileDiff(
            oldPath: input.path,
            newPath: input.path,
            change: .modified,
            isBinary: input.lines == 0,
            hunks: input.lines == 0 ? [] : [hunk(lines: input.lines)],
            blobs: "aaa..bbb"
        )
    }

    /// Hunk s daným počtem změněných řádků, 30 % přidaných a 70 % odebraných.
    private func hunk(lines: Int) -> DiffHunk {
        let added = max(lines * 3 / 10, lines == 0 ? 0 : 1)
        let removed = lines - added
        var rows: [DiffLine] = []
        for index in 0..<added {
            rows.append(DiffLine(kind: .added, oldNumber: nil, newNumber: index + 1, text: "nové"))
        }
        for index in 0..<removed {
            rows.append(DiffLine(kind: .removed, oldNumber: index + 1, newNumber: nil, text: "staré"))
        }
        return DiffHunk(oldStart: 1, oldCount: removed, newStart: 1, newCount: added,
                        heading: "", lines: rows)
    }

    /// Hunk, ve kterém **nová čísla řádků jdou 1…N**: první řádek je přidaný, zbytek kontext.
    /// Vlákno se kotví na nové číslo (`Policy.matches`), takže bez toho by u hunku ze samých
    /// odebraných řádků nemělo na co sednout — a `changedLines` je tu jednička, což na podíl
    /// nemá vliv: ten se počítá z **pořadí řádku v diffu**, ne z počtu změn.
    private func spanningHunk(rows: Int) -> DiffHunk {
        let lines = (0..<rows).map { index in
            DiffLine(
                kind: index == 0 ? .added : .context,
                oldNumber: index == 0 ? nil : index,
                newNumber: index + 1,
                text: "řádek \(index + 1)"
            )
        }
        return DiffHunk(oldStart: 1, oldCount: max(rows - 1, 0), newStart: 1, newCount: rows,
                        heading: "", lines: lines)
    }

    private func thread(path: String, line: Int) -> ReviewThread {
        ReviewThread(
            id: "t-\(path)-\(line)",
            path: path,
            line: line,
            originalLine: line,
            side: .right,
            isResolved: false,
            isOutdated: false,
            comments: ConversationPage(items: [], total: 0, hasNextPage: false)
        )
    }
}
