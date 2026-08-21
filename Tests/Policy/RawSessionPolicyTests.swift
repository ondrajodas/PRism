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
    @Test("Z 53MB souboru se čtou poslední 4 MB")
    func aHugeFileIsReadFromTheEnd() {
        let total = 53_300_000
        let window = Policy.rawSessionWindow(fileBytes: total)

        #expect(window.length == Policy.rawSessionWindowBytes)
        #expect(window.offset == total - Policy.rawSessionWindowBytes)
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
    @Test("Chybějící transcript nenabídne opakování ani Finder")
    func missingOffersNoRetry() {
        let actions = Policy.rawSessionActions(for: .missing)

        #expect(!actions.contains(.reload))
        #expect(!actions.contains(.revealInFinder))
        #expect(!actions.contains(.copyTranscript))
        #expect(actions.contains(.close))
    }

    @Test("Nečitelný transcript nabídne opakování i Finder — soubor tam pořád leží")
    func unreadableOffersBoth() {
        let actions = Policy.rawSessionActions(for: .unreadable("nic"))

        #expect(actions.contains(.reload))
        #expect(actions.contains(.revealInFinder))
        #expect(!actions.contains(.copyTranscript))
    }

    /// U běžící session je prázdno **dočasný** stav, takže `Načíst znovu` smysl má. `Ukázat
    /// v Finderu` jedině tehdy, když v souboru nějaké bajty jsou.
    @Test("Prázdný transcript nabídne opakování, Finder až s bajty")
    func emptyOffersRetry() {
        #expect(Policy.rawSessionActions(for: .empty(bytes: 0)).contains(.reload))
        #expect(!Policy.rawSessionActions(for: .empty(bytes: 0)).contains(.revealInFinder))
        #expect(Policy.rawSessionActions(for: .empty(bytes: 12)).contains(.revealInFinder))
    }

    @Test("Zkopírovat přepis je jedině tam, kde přepis je")
    func copyingIsOnlyForAShownTranscript() {
        let states: [RawTranscriptState] = [
            .loading, .missing, .unreadable("nic"), .empty(bytes: 0), .empty(bytes: 5),
        ]
        for state in states {
            #expect(!Policy.rawSessionActions(for: state).contains(.copyTranscript))
        }
        #expect(Policy.rawSessionActions(for: .shown(RawTranscript())).contains(.copyTranscript))
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
