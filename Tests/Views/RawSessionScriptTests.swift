import AppKit
import SwiftUI
import Testing

@testable import PRism

/// Sazba přepisu surové session (#327).
///
/// Testuje se **to, co se doopravdy nasadí do textu**, ne token v paletě — u #393 se ukázalo, že
/// `DiffPaletteTests` měřily kontrast `Palette.ink` celou dobu a procházely, protože se ta barva do
/// textu nenasazovala. K měření barvy proto patří i tvrzení, že se do textu dostane.
@Suite("Přepis — sazba a kopie")
struct RawSessionScriptTests {
    private func transcript(
        events: [TranscriptEvent],
        omittedBytes: Int = 0,
        fileBytes: Int = 1_000
    ) -> RawTranscript {
        RawTranscript(events: events, omittedBytes: omittedBytes, fileBytes: fileBytes)
    }

    private func event(
        _ kind: TranscriptEvent.Kind,
        subject: String? = nil,
        body: String? = nil,
        cut: String? = nil,
        denied: Bool = false
    ) -> TranscriptEvent {
        TranscriptEvent(
            id: 0,
            at: Date(timeIntervalSince1970: 1_700_000_000),
            kind: kind,
            subject: subject,
            body: body,
            bodyCut: cut,
            isDenied: denied
        )
    }

    // MARK: - Řádky

    @Test("Hlavička nese čas, druh i to, čeho se týká")
    func theHeaderCarriesTimeKindAndSubject() throws {
        let lines = RawSessionScript.lines(
            of: transcript(events: [event(.tool("Grep"), subject: "-rn getSecret src")])
        )

        let header = try #require(lines.first)
        #expect(header.runs.map(\.role) == [.time, .kind, .subject])
        #expect(header.runs[1].text == "Grep")
        #expect(header.runs[2].text == "-rn getSecret src")
        #expect(!header.indented)
    }

    /// Sloupec se nesmí rozjet a nic se nesmí domýšlet — `last-prompt` čas nenese vůbec.
    @Test("Událost bez času dostane prázdno o téže šířce")
    func anEventWithoutATimeKeepsTheColumn() throws {
        let withTime = RawSessionScript.lines(of: transcript(events: [event(.prose)]))
        let without = RawSessionScript.lines(
            of: transcript(events: [TranscriptEvent(id: 0, at: nil, kind: .prose)])
        )

        #expect(try #require(withTime.first).runs[0].text.count == 8)
        #expect(try #require(without.first).runs[0].text.count == 8)
        #expect(try #require(without.first).runs[0].text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("Tělo je odsazený řádek, ořez těla druhý")
    func theBodyAndItsCutAreIndented() {
        let lines = RawSessionScript.lines(
            of: transcript(events: [
                event(.tool("Read"), subject: "Cart.php", body: "řádek\nřádek", cut: "… + 5 řádků"),
            ])
        )

        #expect(lines.count == 3)
        #expect(lines[1].runs.map(\.role) == [.body])
        #expect(lines[1].indented)
        #expect(lines[2].runs.map(\.role) == [.cut])
        #expect(lines[2].indented)
    }

    /// **Tělo je jeden řádek s vnitřními zlomy**, ne řádek na každý zlom: po ořezu má 8 kB, takže
    /// rozpad na položky by byl tisíc alokací na událost. Odsazení za to nic neplatí — `headIndent`
    /// je vlastnost odstavce.
    @Test("Vícedílné tělo nezvětší počet řádků skriptu")
    func aMultilineBodyIsStillOneScriptLine() {
        let body = (0..<400).map { "řádek \($0)" }.joined(separator: "\n")

        let lines = RawSessionScript.lines(of: transcript(events: [event(.tool("Bash"), body: body)]))

        #expect(lines.count == 2)
    }

    /// **Druhé ze tří přiznání zkrácení.** Tiše zkrácený přepis tvrdí, že session začala uprostřed.
    @Test("Řez na začátku textu je první řádek, a jedině u zkráceného okna")
    func theTopCutIsTheFirstLine() throws {
        let cut = RawSessionScript.lines(
            of: transcript(events: [event(.prose)], omittedBytes: 5_100_000, fileBytes: 9_100_000)
        )
        let whole = RawSessionScript.lines(of: transcript(events: [event(.prose)]))

        #expect(try #require(cut.first).runs.map(\.role) == [.topCut])
        #expect(try #require(cut.first).runs[0].text.contains("nevešlo"))
        // Neořezané okno žádný řez nedostane — první řádek je hlavička první události.
        #expect(try #require(whole.first).runs.map(\.role) == [.time, .kindAccent])
    }

    /// Štítek, ne červený řádek — a **tentýž text jako ve výpisu kroků**, aby se z okna poznalo, že
    /// jde o totéž.
    @Test("Odmítnutý nástroj má štítek za detailem, a jméno zůstává obyčejné")
    func aDeniedToolGetsALabel() throws {
        let lines = RawSessionScript.lines(
            of: transcript(events: [event(.tool("Bash"), subject: "gh pr view", denied: true)])
        )

        let header = try #require(lines.first)
        #expect(header.runs.map(\.role) == [.time, .kind, .subject, .denied])
        #expect(header.runs.last?.text == ReviewerLaneText.deniedStep)
        // Jméno nástroje **není** červené — to je celý rozdíl proti poplachu.
        #expect(header.runs[1].role == .kind)
    }

    @Test("Próza a ReportFindings nesou akcent, uvažování a systém jsou tišší")
    func kindColoursFollowWhatTheKindMeansElsewhere() {
        func role(_ kind: TranscriptEvent.Kind) -> RawSessionScript.Role? {
            RawSessionScript.lines(of: transcript(events: [event(kind)])).first?.runs[1].role
        }

        #expect(role(.prose) == .kindAccent)
        #expect(role(.report) == .kindAccent)
        #expect(role(.thinking) == .kindDim)
        #expect(role(.system("attachment")) == .kindDim)
        #expect(role(.tool("Read")) == .kind)
        #expect(role(.unreadable) == .kind)
    }

    // MARK: - Kopie

    /// `Zkopírovat přepis` a vysázený text jsou **jedna pravda** — dvě samostatná skládání by se
    /// rozešla první úpravou hlavičky.
    @Test("Kopie obsahuje to, co je vidět")
    func theCopyCarriesWhatIsVisible() {
        let lines = RawSessionScript.lines(
            of: transcript(events: [
                event(.tool("Bash"), subject: "ls", body: "Cart.php", cut: "… + 2 řádky"),
                event(.prose, subject: "próza · 0,4 kB", body: "nesedí mi to"),
            ])
        )

        let plain = RawSessionScript.plain(lines)

        #expect(plain.contains("Bash  ls"))
        #expect(plain.contains("Cart.php"))
        #expect(plain.contains("… + 2 řádky"))
        #expect(plain.contains("nesedí mi to"))
        #expect(TextLines.content(plain).count == 5)
    }

    // MARK: - Sazba

    /// **V AppKitu není „bez barvy“ dědění, ale černá** (#393): `NSAttributedString` bez
    /// `.foregroundColor` se kreslí černě, takže by přepis byl v tmavém režimu černý na tmavém.
    /// **Mezery mezi kusy hlavičky musí být i ve sazbě**, ne jen v kopii: bez nich se z hlavičky
    /// stane `23:13:36Bashgh pr view 412` — chyba, kterou zelené testy neukázaly a render ano.
    @Test("Vysázená hlavička má mezery na týchž místech jako kopie")
    func theTypesetHeaderHasTheSameGapsAsTheCopy() {
        let lines = RawSessionScript.lines(
            of: transcript(events: [event(.tool("Bash"), subject: "gh pr view 412", denied: true)])
        )

        #expect(RawSessionScript.attributed(lines).string == RawSessionScript.plain(lines))
    }

    @Test("Barva se nasadí u každého kusu textu")
    func everyRunGetsAColour() throws {
        let attributed = RawSessionScript.attributed(
            RawSessionScript.lines(
                of: transcript(
                    events: [event(.tool("Bash"), subject: "ls", body: "Cart.php", denied: true)],
                    omittedBytes: 200,
                    fileBytes: 4_000_000
                )
            )
        )

        var uncoloured = 0
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, _ in
            if attributes[.foregroundColor] == nil { uncoloured += 1 }
        }
        #expect(uncoloured == 0)
        #expect(attributed.length > 0)
    }

    /// Ta barva musí být z palety návrhu, ne systémová: `labelColor` je poloprůhledný a přes barevné
    /// pozadí se složí jinak (#393).
    @Test("Tělo dostane paletový ink2, ne systémový labelColor")
    func theBodyUsesThePaletteColour() throws {
        let attributed = RawSessionScript.attributed(
            RawSessionScript.lines(of: transcript(events: [event(.tool("Bash"), body: "Cart.php")]))
        )
        let text = attributed.string
        let range = try #require(text.range(of: "Cart.php"))
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)

        let colour = attributed.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor

        #expect(colour == NSColor(Palette.ink2))
    }

    @Test("Tělo je odsazené, hlavička ne")
    func indentationFollowsTheRole() throws {
        let attributed = RawSessionScript.attributed(
            RawSessionScript.lines(of: transcript(events: [event(.tool("Bash"), body: "Cart.php")]))
        )
        let text = attributed.string
        let bodyRange = try #require(text.range(of: "Cart.php"))
        let bodyOffset = text.distance(from: text.startIndex, to: bodyRange.lowerBound)

        let header = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let body = attributed.attribute(.paragraphStyle, at: bodyOffset, effectiveRange: nil) as? NSParagraphStyle

        #expect(header?.headIndent == 0)
        #expect(body?.headIndent == RawSessionScript.bodyIndent)
        #expect(body?.firstLineHeadIndent == RawSessionScript.bodyIndent)
    }

    /// Prokládání drží `line-height: 1.6` z návrhu — jedno místo pro celý přepis, ne na každý run
    /// jiné.
    @Test("Prokládání je stejné v hlavičce i v těle")
    func lineSpacingIsTheSameEverywhere() throws {
        let attributed = RawSessionScript.attributed(
            RawSessionScript.lines(of: transcript(events: [event(.tool("Bash"), body: "Cart.php")]))
        )

        let header = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        #expect(header?.lineSpacing == RawSessionScript.lineSpacing)
    }

    // MARK: - Stráž sazby

    /// **`updateNSView` chodí i tehdy, když se hodnota nezměnila** (#393) — a tady je konkrétní
    /// pohon: patička sheetu se každé dvě vteřiny ptá na velikost souboru, takže se `body` přepočítá
    /// i nad nezměněným přepisem. Bez stráže by se při každém tiknutí sázely znovu megabajty.
    @Test("Tik přírůstku přepis nepřesází")
    @MainActor
    func theGrowthTickDoesNotRetypeset() {
        let coordinator = TranscriptTextView.Coordinator()
        let snapshot = transcript(events: [event(.tool("Bash"), body: "Cart.php")])

        #expect(TranscriptTextView.needsTypesetting(coordinator, transcript: snapshot, scheme: .dark))
        #expect(!TranscriptTextView.needsTypesetting(coordinator, transcript: snapshot, scheme: .dark))
    }

    /// Nový snímek po `Načíst znovu` se přesázet **musí** — jinak by tlačítko nic nedělalo.
    @Test("Nový snímek se přesází")
    @MainActor
    func aFreshSnapshotIsTypesetAgain() {
        let coordinator = TranscriptTextView.Coordinator()
        let first = transcript(events: [event(.prose, body: "první")])
        let second = transcript(events: [event(.prose, body: "druhá")])

        #expect(TranscriptTextView.needsTypesetting(coordinator, transcript: first, scheme: .dark))
        #expect(TranscriptTextView.needsTypesetting(coordinator, transcript: second, scheme: .dark))
    }

    /// A přepnutí režimu taky: barvy se berou z palety při sazbě, takže bez přesázení by zůstaly ty
    /// z minulého režimu.
    @Test("Přepnutí světlého a tmavého režimu přepis přesází")
    @MainActor
    func switchingTheSchemeRetypesets() {
        let coordinator = TranscriptTextView.Coordinator()
        let snapshot = transcript(events: [event(.prose, body: "text")])

        #expect(TranscriptTextView.needsTypesetting(coordinator, transcript: snapshot, scheme: .dark))
        #expect(TranscriptTextView.needsTypesetting(coordinator, transcript: snapshot, scheme: .light))
    }
}
