import Foundation
import Testing

@testable import PRism

/// Krájení okna transcriptu (#327).
///
/// Čísla ve testech jsou ta **změřená** na 922 transcriptech pod `~/.claude/projects`: největší má
/// 53,3 MB při 2 348 řádcích a nejdelší řádek 7,5 MB. Právě z těch dvou plyne, proč je jednotkou
/// bajt a proč je druhý strop na jednu událost — takže se testuje i ten pathologický případ, kdy je
/// jeden řádek delší než celé okno.
@Suite("Policy — okno transcriptu")
struct RawSessionWindowTests {
    @Test("Soubor pod stropem se čte celý a nic se nepřiznává")
    func aSmallFileIsReadWhole() {
        let window = Policy.rawSessionWindow(fileBytes: 271_000)

        #expect(window.offset == 0)
        #expect(window.length == 271_000)
    }

    @Test("Přesně na stropu se ještě čte celý")
    func exactlyAtTheLimitIsWhole() {
        let window = Policy.rawSessionWindow(fileBytes: Policy.rawSessionWindowBytes)

        #expect(window.offset == 0)
        #expect(window.length == Policy.rawSessionWindowBytes)
    }

    /// Největší změřený transcript. **Nesmí z toho být stav „moc velký“** — soubor je lokální, takže
    /// se dá čtení začít od konce.
    @Test("Z 53MB souboru se čtou poslední 4 MB a bajt před nimi")
    func aHugeFileIsReadFromTheEnd() {
        let total = 53_300_000
        let window = Policy.rawSessionWindow(fileBytes: total)

        // O bajt víc, a je to sonda na hranici řádku — viz `rawSessionWindow`.
        #expect(window.length == Policy.rawSessionWindowBytes + 1)
        #expect(window.offset == total - Policy.rawSessionWindowBytes - 1)
        // Okno pořád končí na konci souboru; sonda je jediný bajt navíc, a to zpředu.
        #expect(window.offset + window.length == total)
    }

    /// Soubor **o jeden bajt nad stropem**: sonda se ještě vejde, takže se `offset` nesmí dostat do
    /// minusu ani okno přerůst soubor.
    @Test("Soubor o bajt nad stropem se čte celý, i se sondou")
    func oneByteOverTheLimit() {
        let total = Policy.rawSessionWindowBytes + 1
        let window = Policy.rawSessionWindow(fileBytes: total)

        #expect(window.offset == 0)
        #expect(window.length == total)
    }

    @Test("Prázdný a nesmyslně velký soubor dají prázdné okno, ne pád")
    func emptyAndNonsenseSizes() {
        #expect(Policy.rawSessionWindow(fileBytes: 0) == (0, 0))
        #expect(Policy.rawSessionWindow(fileBytes: -5) == (0, 0))
    }

    // MARK: - Zarovnání na začátek řádku

    @Test("Začátek okna se zahodí až za první zakončení řádku")
    func alignmentDropsThePartialFirstLine() {
        let window = Data("zbytek řádku\n{\"type\":\"user\"}\n".utf8)

        // „zbytek řádku“ je 14 bajtů (`ř` i `á` mají dva) a k nim `\n`.
        #expect(Policy.rawSessionPrefixDrop(window, isTail: true) == 15)
    }

    /// Okno, které je celý soubor, začíná na začátku řádku z definice — a zahodit z něj cokoli by
    /// znamenalo zahodit první událost session.
    @Test("Neořezané okno se nezarovnává")
    func theWholeFileIsNotAligned() {
        let window = Data("{\"type\":\"user\"}\n".utf8)

        #expect(Policy.rawSessionPrefixDrop(window, isTail: false) == 0)
    }

    /// Ten změřený případ jednoho řádku o 7,5 MB. Zahodit celé okno by znamenalo prázdný sheet nad
    /// souborem, ve kterém něco je.
    @Test("Okno bez jediného zakončení řádku se nezahodí")
    func aWindowWithoutAnyLineBreakSurvives() {
        let window = Data(String(repeating: "x", count: 4096).utf8)

        #expect(Policy.rawSessionPrefixDrop(window, isTail: true) == 0)
    }

    /// `offset` padne doprostřed znaku. Bez zahození pokračovacích bajtů by dekódování selhalo
    /// a okno by hlásilo „soubor nemá platné UTF-8“ o souboru, který ho má.
    @Test("Rozpůlený znak na začátku okna se zahodí po bajtech")
    func aSplitCharacterAtTheStartIsDropped() {
        // „ř“ je `0xC5 0x99`; okno začne jeho druhým bajtem.
        let window = Data([0x99] + Array("xy".utf8))

        #expect(Policy.rawSessionPrefixDrop(window, isTail: true) == 1)
    }

    @Test("Zahodí se nejvýš tři pokračovací bajty — delší kódový bod v UTF-8 není")
    func atMostThreeContinuationBytes() {
        let window = Data([0x80, 0x80, 0x80, 0x80, 0x41])

        #expect(Policy.rawSessionPrefixDrop(window, isTail: true) == 3)
    }

    @Test("Prázdné okno se zarovnává na nulu, ne na pád")
    func anEmptyWindow() {
        #expect(Policy.rawSessionPrefixDrop(Data(), isTail: true) == 0)
    }

    /// Dělení řádků drží `TextLines` a to zná `LF`, `CRLF` i samotné `CR` (#295) — kdyby zarovnání
    /// hledalo jen `LF`, začalo by okno transcriptu s `CR` uprostřed záznamu a jeho první událost by
    /// byla nečitelná, přestože soubor je v pořádku. Nálezem Copilota na #408.
    @Test("Zarovnání zná CRLF i samotné CR, ne jen LF")
    func alignmentKnowsEveryLineEnding() {
        // `CRLF` je **jedno** zakončení: kdyby se spotřebovalo jen `CR`, okno by začalo osamoceným
        // `LF`, tedy prázdným řádkem.
        #expect(Policy.rawSessionPrefixDrop(Data("ab\r\ncd".utf8), isTail: true) == 4)
        #expect(Policy.rawSessionPrefixDrop(Data("ab\rcd".utf8), isTail: true) == 3)
        #expect(Policy.rawSessionPrefixDrop(Data("ab\ncd".utf8), isTail: true) == 3)
    }

    /// Řádek delší než celé okno končí zakončením na **posledním** bajtu okna, takže by hledání
    /// prvního zakončení zahodilo všechno až na nic — a to platí i pro `CRLF` na konci.
    @Test("Zakončení na samém konci okna se nezahodí")
    func aLineEndingAtTheVeryEndIsKept() {
        #expect(Policy.rawSessionPrefixDrop(Data("abcd\n".utf8), isTail: true) == 0)
        #expect(Policy.rawSessionPrefixDrop(Data("abcd\r\n".utf8), isTail: true) == 0)
    }
}

/// Strop na jednu událost a přiznání jeho ořezu (#327).
@Suite("Policy — strop na jednu událost")
struct RawSessionBodyTests {
    @Test("Krátké tělo projde celé a nic se nepřiznává")
    func aShortBodyPassesThrough() {
        let body = Policy.rawSessionBody("první\ndruhý")

        #expect(body.text == "první\ndruhý")
        #expect(body.cut == nil)
    }

    @Test("Prázdné tělo se nekreslí vůbec")
    func anEmptyBodyIsNothing() {
        #expect(Policy.rawSessionBody("") == RawSessionBody(text: nil, cut: nil))
        #expect(Policy.rawSessionBody("\n\n  ") == RawSessionBody(text: nil, cut: nil))
    }

    /// Zakončení na konci nese v transcriptu skoro každý blok, a v přepisu by z něj byly prázdné
    /// řádky mezi událostmi.
    @Test("Zakončení řádků na konci se sundá")
    func trailingNewlinesGoAway() {
        #expect(Policy.rawSessionBody("text\n\n").text == "text")
        #expect(Policy.rawSessionBody("text\r\n").text == "text")
    }

    /// **Mezery na konci řádku jsou obsah**, ne šum: tělo se má ukázat tak, jak v transcriptu stojí,
    /// a u výstupu příkazu se na koncové mezery dá narazit. Sundávají se jen zakončení řádků.
    /// Nálezem Copilota na #408.
    @Test("Mezery na konci se nesundávají")
    func trailingSpacesStay() {
        #expect(Policy.rawSessionBody("text   \n").text == "text   ")
        #expect(Policy.rawSessionBody("text\t").text == "text\t")
    }

    @Test("Řeže se na celém řádku a řekne se, kolik řádků zbylo")
    func cutsOnALineBoundaryAndCountsLines() {
        // Deset řádků po deseti bajtech; strop 25 bajtů vezme dva (11 + 11 = 22).
        let text = (0..<10).map { _ in "abcdefghij" }.joined(separator: "\n")
        let body = Policy.rawSessionBody(text, limit: 25)

        #expect(body.text == "abcdefghij\nabcdefghij")
        #expect(body.cut == "… + 8 řádků nad strop události")
    }

    /// `CRLF` je ve Swiftu **jeden `Character`**, ale **dva bajty** — a strop se počítá v bajtech.
    /// Kdyby se za zakončení přičítala jednička, ořez by lezl nad strop.
    @Test("CRLF se do stropu počítá dvěma bajty")
    func crlfCountsAsTwoBytes() {
        let text = "abcd\r\nefgh\r\nijkl"
        let body = Policy.rawSessionBody(text, limit: 12)

        // `abcd` + CRLF = 6, `efgh` + CRLF = 12 — druhý řádek se vejde přesně, a zakončení za ním
        // do ukázaného těla nepatří.
        #expect(body.text == "abcd\r\nefgh")
        #expect(body.cut == "… + 4 bajty nad strop události")
    }

    /// Jeden `tool_result` o 7,5 MB je **jeden řádek**, takže „+ 1 řádek“ by nic neřeklo.
    @Test("Řez uprostřed dlouhého řádku hlásí bajty")
    func cuttingInsideALongLineReportsBytes() {
        let body = Policy.rawSessionBody(String(repeating: "x", count: 20_000), limit: 8192)

        #expect(body.text?.count == 8192)
        #expect(body.cut == "… + 12 kB nad strop události")
    }

    /// Zbytek nad megabajt se hlásí velikostí, i když je řez na celém řádku: počet řádků nad
    /// megabajtem přestává být rozumná míra toho, kolik toho chybí.
    @Test("Zbytek nad megabajt se hlásí velikostí")
    func aHugeRemainderReportsBytes() throws {
        let long = String(repeating: "y", count: 600_000)
        let body = Policy.rawSessionBody("krátký\n\(long)\n\(long)", limit: 8192)

        #expect(body.text == "krátký")
        let cut = try #require(body.cut)
        #expect(cut.hasSuffix("nad strop události"))
        #expect(cut.contains("MB"))
    }

    /// Po řezu uprostřed řádku začíná zbytek půlkou řádku, takže by se počítal jako celý — a číslo
    /// by nesedělo.
    @Test("Po řezu uprostřed řádku se hlásí bajty, i když za ním jsou celé řádky")
    func aMidLineCutAlwaysReportsBytes() throws {
        let body = Policy.rawSessionBody("\(String(repeating: "x", count: 40))\nkrátký\nkrátký", limit: 20)

        #expect(body.text?.count == 20)
        let cut = try #require(body.cut)
        #expect(cut.hasSuffix("nad strop události"))
        // **Velikost, ne řádky**: zbytek začíná půlkou řádku, takže by se počítal jako celý.
        #expect(!cut.contains("řád"))
    }

    @Test("Přesně na stropu se neřeže")
    func exactlyAtTheLimitIsNotCut() {
        let body = Policy.rawSessionBody(String(repeating: "x", count: 8192), limit: 8192)

        #expect(body.cut == nil)
    }

    /// Ořez po znacích, ne po bajtech: rozpůlený kódový bod v `NSTextView`u nakreslí otazník
    /// v kosočtverci a ve zkopírovaném přepisu je z něj vadné UTF-8.
    @Test("Řez uprostřed řádku neroztrhne znak")
    func aMidLineCutKeepsCharactersWhole() throws {
        // „ř“ jsou dva bajty, takže na stropu 5 se vejdou dvě a šestý bajt by byl půlka třetího.
        let body = Policy.rawSessionBody(String(repeating: "ř", count: 100), limit: 5)

        let text = try #require(body.text)
        #expect(text == "řř")
        #expect(String(data: Data(text.utf8), encoding: .utf8) == text)
    }
}

/// Který stav sheetu co nabídne (#327).
@Suite("Policy — stavy surové session")
struct RawSessionStateTests {
    @Test("Snímek s událostmi se ukazuje")
    func aSnapshotWithEventsIsShown() {
        let transcript = RawTranscript(
            events: [TranscriptEvent(id: 0, at: nil, kind: .prose, subject: "próza · 4 B")],
            fileBytes: 400
        )

        #expect(Policy.rawSessionState(of: transcript) == .shown(transcript))
    }

    /// **Prázdný sheet by vypadal jako „session nic nedělala“** — a `TranscriptStore` ten stav sám
    /// nerozlišuje, protože prázdný soubor se přečte v pořádku a vydá nic.
    @Test("Snímek bez událostí je prázdný stav, ne prázdná obrazovka")
    func aSnapshotWithoutEventsIsEmpty() {
        #expect(Policy.rawSessionState(of: RawTranscript()) == .empty(bytes: 0))
        #expect(
            Policy.rawSessionState(of: RawTranscript(fileBytes: 900)) == .empty(bytes: 900)
        )
    }

    /// Konečná odpověď **bez** `Načíst znovu`: nabízet opakování u odpovědi, která se nezmění, je
    /// slib, který se nemá čím naplnit. A bez `Ukázat v Finderu`, protože soubor tam není.
    @Test("Chybějící transcript nabídne jedině Zavřít")
    func missingOffersNothingButClosing() {
        #expect(Policy.rawSessionActions(for: .missing) == [.close])
    }

    @Test("Nečitelný transcript nabídne opakování i Finder — soubor tam pořád leží")
    func unreadableOffersBoth() {
        #expect(Policy.rawSessionActions(for: .unreadable("nic")) == [.close, .revealInFinder, .reload])
    }

    /// U běžící session je prázdno **dočasný** stav, takže `Načíst znovu` smysl má. `Ukázat
    /// v Finderu` jedině tehdy, když v souboru nějaké bajty jsou.
    @Test("Prázdný transcript nabídne opakování, Finder až s bajty")
    func emptyOffersRetry() {
        #expect(Policy.rawSessionActions(for: .empty(bytes: 0)).contains(.reload))
        #expect(!Policy.rawSessionActions(for: .empty(bytes: 0)).contains(.revealInFinder))
        #expect(Policy.rawSessionActions(for: .empty(bytes: 12)).contains(.revealInFinder))
    }

    /// U chybového stavu je odpověď v hlášce, ne v tom, co se dá odsud vzít pryč — a kopírovat cestu
    /// k souboru, který není, je nabídka jít se podívat na nic.
    @Test("Zkopírovat přepis ani cestu nenabízí žádný chybový stav")
    func copyingIsOnlyForAShownTranscript() {
        let states: [RawTranscriptState] = [
            .loading, .missing, .unreadable("nic"), .empty(bytes: 0), .empty(bytes: 5),
        ]
        for state in states {
            #expect(!Policy.rawSessionActions(for: state).contains(.copyTranscript))
            #expect(!Policy.rawSessionActions(for: state).contains(.copyPath))
        }
        let shown = Policy.rawSessionActions(for: .shown(RawTranscript()))
        #expect(shown.contains(.copyTranscript))
        #expect(shown.contains(.copyPath))
    }

    /// Zavřít musí jít z každého stavu — sheet, ze kterého se nedá odejít, je horší než chybějící.
    @Test("Zavřít nabízí každý stav")
    func everyStateCanBeClosed() {
        let states: [RawTranscriptState] = [
            .loading,
            .shown(RawTranscript()),
            .missing,
            .unreadable("nic"),
            .empty(bytes: 0),
        ]
        for state in states {
            #expect(Policy.rawSessionActions(for: state).contains(.close))
        }
    }

    // MARK: - Přírůstek

    @Test("Přírůstek se hlásí jen tehdy, když soubor vyrostl")
    func growthOnlyWhenItGrew() {
        #expect(Policy.rawSessionGrowth(snapshot: 100, now: 350) == 250)
        #expect(Policy.rawSessionGrowth(snapshot: 100, now: 100) == nil)
        #expect(Policy.rawSessionGrowth(snapshot: 100, now: nil) == nil)
    }

    /// `přibylo −2 MB` je věta, která nic neznamená — a soubor umí i zmenšit (úklid cache).
    @Test("Zmenšený soubor přírůstek nehlásí")
    func aShrunkFileReportsNothing() {
        #expect(Policy.rawSessionGrowth(snapshot: 900, now: 100) == nil)
    }

    // MARK: - Bez čeho se tlačítko nekreslí

    @Test("Dráha bez session_id ani bez pracovního stromu tlačítko nedostane")
    func withoutASessionOrWorktreeThereIsNoButton() {
        #expect(Policy.rawSessionTarget(of: lane(session: nil, worktree: nil), slug: "o/r#1") == nil)
        #expect(Policy.rawSessionTarget(of: lane(session: "s", worktree: nil), slug: "o/r#1") == nil)
        #expect(
            Policy.rawSessionTarget(
                of: lane(session: nil, worktree: URL(filePath: "/tmp/w")),
                slug: "o/r#1"
            ) == nil
        )
    }

    /// **Odpověď na nález Copilota, který chtěl tlačítko i mimo výpis kroků** (#408). Tlačítko se
    /// kreslí uvnitř `StepFeedView`, a ten se u dráhy bez osy nekreslí vůbec — jenže dráha bez osy
    /// **nemá pracovní strom**: bere ho z uložené osy (`ReviewerTimeline(_ run:)`), takže bez ní je
    /// `nil` a cíl se nemá z čeho složit. Tlačítko by tedy nebylo co otevřít, ne že by chybělo.
    ///
    /// Je to tvrzení o **invariantu**, ne o kresbě: kdyby se strom začal brát odjinud, tenhle test
    /// spadne a řekne, že se ta úvaha rozešla se skutečností.
    @Test("Dráha bez osy nemá čím cíl složit, i když session zná")
    func aLaneWithoutATimelineHasNoWorktree() {
        // Bez uložené osy, tedy tak, jak vypadají soubory z doby před #203.
        let run = makeStoredRun(skill: "security-review", timeline: nil, sessionID: "abc")
        let timeline = ReviewerTimeline(run)

        #expect(timeline.sessionID == "abc")
        #expect(timeline.entries.isEmpty)
        #expect(timeline.worktree == nil)
    }

    @Test("S obojím se cíl složí")
    func withBothTheTargetIsBuilt() throws {
        let target = try #require(
            Policy.rawSessionTarget(
                of: lane(session: "abc", worktree: URL(filePath: "/tmp/w")),
                slug: "o/r#1"
            )
        )

        #expect(target.sessionID == "abc")
        #expect(target.skill == "security-review")
        #expect(target.slug == "o/r#1")
    }

    private func lane(session: String?, worktree: URL?) -> ReviewerLane {
        ReviewerLane(
            skill: "security-review",
            state: .finished,
            phases: [],
            lastTool: nil,
            finishedAt: nil,
            reportedFindings: nil,
            usage: nil,
            sessionID: session,
            worktree: worktree,
            droppedEntries: 0,
            loadedSkill: nil,
            intentGap: nil,
            entries: [],
            isConfigured: true
        )
    }
}

/// S jakou velikostí se sheet otevře a kdy se natažená velikost ukládá (#327 follow-up).
///
/// Že je sheet **doopravdy roztahovatelný** a že se ideální šířka uplatní, se tady netvrdí — o tom
/// rozhoduje SwiftUI a měří to `RawSessionSheetSizingTests` nad skutečným oknem sheetu.
@Suite("Policy — velikost sheetu s přepisem")
struct RawSessionSheetSizeTests {
    private let screen = CGSize(width: 1_512, height: 944)

    // MARK: - S čím se otevře

    /// Nula znamená **„nic uloženého“**, ne nulový sheet — `@AppStorage` bez zapsané hodnoty vrací
    /// právě ji.
    @Test("Bez uložené velikosti se bere ideální")
    func withoutAStoredSizeTheIdealIsUsed() {
        let size = Policy.rawSessionSheetSize(storedWidth: 0, storedHeight: 0, screen: screen)

        #expect(size.width == Policy.rawSessionSheetIdealWidth)
        #expect(size.height == Policy.rawSessionSheetIdealHeight)
    }

    @Test("Uložená velikost v mezích se vezme, jak je")
    func aStoredSizeIsUsedAsIs() {
        let size = Policy.rawSessionSheetSize(storedWidth: 1_340, storedHeight: 820, screen: screen)

        #expect(size == CGSize(width: 1_340, height: 820))
    }

    /// Ořez **při použití**, ne při zápisu: v `UserDefaults` může být cokoli — ruční editace,
    /// hodnota ze starší verze — a `frame(idealWidth:)` se zápornou hodnotou rozhodí celé okno.
    @Test("Nesmyslná uložená hodnota spadne na ideální velikost")
    func nonsenseFallsBackToTheIdeal() {
        let ideal = CGSize(
            width: Policy.rawSessionSheetIdealWidth,
            height: Policy.rawSessionSheetIdealHeight
        )
        let nonsense: [(Double, Double)] = [
            (0, 0), (-1_200, 800), (1_200, -800), (.nan, 800), (1_200, .nan), (.infinity, .infinity),
        ]
        for (width, height) in nonsense {
            #expect(
                Policy.rawSessionSheetSize(storedWidth: width, storedHeight: height, screen: screen) == ideal,
                "\(width)×\(height) se nevrátilo na ideální velikost."
            )
        }
    }

    @Test("Pod podlahu se sheet neotevře, ani když je uložená menší")
    func aStoredSizeNeverGoesBelowTheFloor() {
        let size = Policy.rawSessionSheetSize(storedWidth: 300, storedHeight: 100, screen: screen)

        #expect(size.width == Policy.rawSessionSheetMinWidth)
        #expect(size.height == Policy.rawSessionSheetMinHeight)
    }

    /// **Natáhne se na jedné obrazovce, otevírá na druhé.** Bez tohohle ořezu by 3 000 bodů
    /// z ultrawide monitoru byl na notebooku sheet přes celou plochu a přes hrany.
    @Test("Uložená velikost se ořeže o okraje obrazovky")
    func aStoredSizeIsClampedToTheScreen() {
        let size = Policy.rawSessionSheetSize(storedWidth: 3_000, storedHeight: 2_000, screen: screen)

        #expect(size.width == screen.width - Policy.rawSessionSheetScreenMargin)
        #expect(size.height == screen.height - Policy.rawSessionSheetScreenMargin)
    }

    /// Na displeji, kam se podlaha nevejde, rozhoduje **podlaha**, ne okraj — jinak by z ořezu
    /// vyšel sheet užší, než v jakém se dá přepis přečíst (a při hodně malé obrazovce i záporný).
    @Test("Na malé obrazovce rozhoduje podlaha, ne okraj")
    func onATinyScreenTheFloorWins() {
        let size = Policy.rawSessionSheetSize(
            storedWidth: 1_200,
            storedHeight: 900,
            screen: CGSize(width: 600, height: 400)
        )

        #expect(size.width == Policy.rawSessionSheetMinWidth)
        #expect(size.height == Policy.rawSessionSheetMinHeight)
    }

    /// Ideální velikost se ořezává **taky** — na malém displeji se sheet nemá otevřít přes hrany.
    /// Ořezává se každý rozměr zvlášť, protože displej bývá nízký a široký, ne o obojí menší.
    @Test("Ideální velikost se na malou obrazovku ořeže")
    func theIdealIsClampedToo() {
        let size = Policy.rawSessionSheetSize(
            storedWidth: 0,
            storedHeight: 0,
            screen: CGSize(width: 1_000, height: 800)
        )

        #expect(size.width == 1_000 - Policy.rawSessionSheetScreenMargin)
        #expect(size.height == 800 - Policy.rawSessionSheetScreenMargin)

        // Na širokém a nízkém displeji se ořeže jen výška.
        let wide = Policy.rawSessionSheetSize(
            storedWidth: 0,
            storedHeight: 0,
            screen: CGSize(width: 3_440, height: 800)
        )
        #expect(wide.width == Policy.rawSessionSheetIdealWidth)
        #expect(wide.height == 800 - Policy.rawSessionSheetScreenMargin)
    }

    /// Bez známé obrazovky zbývá **pojistka proti nesmyslu v `UserDefaults`**, ne návrhové
    /// rozhodnutí: skutečný strop je obrazovka.
    @Test("Bez známé obrazovky drží uloženou velikost jen pojistka")
    func withoutAScreenOnlyTheCapHolds() {
        let size = Policy.rawSessionSheetSize(storedWidth: 99_000, storedHeight: 99_000, screen: nil)

        #expect(size == Policy.rawSessionSheetCap)
        #expect(
            Policy.rawSessionSheetSize(storedWidth: 1_340, storedHeight: 820, screen: nil)
                == CGSize(width: 1_340, height: 820)
        )
    }

    // MARK: - Kdy se ukládá

    /// Velikost, o kterou si aplikace řekla sama, **není volba uživatele** — kdyby se ukládala,
    /// přepsala by nulu („nic uloženého“) na konkrétní číslo a výchozí velikost by přestala vycházet
    /// z obrazovky.
    @Test("Velikost, se kterou se sheet otevřel, se neukládá")
    func theOpeningSizeIsNotStored() {
        let opened = CGSize(width: 1_180, height: 760)

        #expect(Policy.rawSessionSheetResize(opened: opened, measured: opened) == nil)
        // Zaokrouhluje se na obou stranách, takže půl bodu z rozvržení není změna.
        #expect(
            Policy.rawSessionSheetResize(
                opened: opened,
                measured: CGSize(width: 1_180.4, height: 759.6)
            ) == nil
        )
    }

    @Test("Natažená velikost se uloží zaokrouhlená")
    func aDraggedSizeIsStoredRounded() {
        let size = Policy.rawSessionSheetResize(
            opened: CGSize(width: 1_180, height: 760),
            measured: CGSize(width: 1_442.6, height: 903.2)
        )

        #expect(size == CGSize(width: 1_443, height: 903))
    }

    /// Pod podlahu se sheet nedostane (je to `contentMinSize` okna), takže menší číslo je mezistav
    /// rozvržení, ne velikost okna — a nesmyslné rozměry se neukládají vůbec.
    @Test("Rozměr pod podlahou ani nesmysl se neuloží")
    func nonsenseIsNeverStored() {
        let opened = CGSize(width: 1_180, height: 760)
        let refused: [CGSize] = [
            CGSize(width: 700, height: 900),
            CGSize(width: 900, height: 400),
            CGSize(width: 0, height: 0),
            CGSize(width: CGFloat.nan, height: 800),
            CGSize(width: 1_000, height: CGFloat.infinity),
        ]
        for measured in refused {
            #expect(
                Policy.rawSessionSheetResize(opened: opened, measured: measured) == nil,
                "\(measured) se uložilo, i když se uložit nemělo."
            )
        }
    }

    /// **Podlaha sama nesmysl není**: kdo si sheet stáhne až na ni, má ji mít zapamatovanou. Že se
    /// při otevření neuloží ta podlaha z **prvního průchodu rozvržení**, drží odmlka ve view — je na
    /// to `RawSessionSheetSizingTests.openingAloneStoresNothing`.
    @Test("Stažení až na podlahu se uloží")
    func draggingDownToTheFloorIsStored() {
        let size = Policy.rawSessionSheetResize(
            opened: CGSize(width: 1_180, height: 760),
            measured: CGSize(
                width: Policy.rawSessionSheetMinWidth,
                height: Policy.rawSessionSheetMinHeight
            )
        )

        #expect(size == CGSize(width: 720, height: 420))
    }
}
