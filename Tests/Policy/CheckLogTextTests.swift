import Foundation
import Testing

@testable import PRism

/// Příprava logu jobu (#214) — číslo jobu z odkazu, ANSI, timestampy, ořez od konce a strop.
///
/// Všechno čisté funkce, takže výčtem. Co se dá pokazit potichu: **utnout log a neříct to**
/// (tvrdilo by to, že job začal uprostřed), **vzít číslo běhu místo jobu** (log běhu je log všech
/// jeho jobů, u změřeného PR 23) a **pustit ke stažení log nad stropem** (osm mega na jedno
/// kliknutí).
@Suite("Příprava logu checku")
struct CheckLogTextTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    // MARK: - Číslo jobu z odkazu

    /// Tvar, jaký `gh pr checks` vrací u jobů z Actions.
    @Test("Job ID se vytáhne z odkazu na job")
    func readsTheJobID() {
        #expect(Policy.jobID(from: url(
            "https://github.com/keboola/job-queue-daemon/actions/runs/30274771802/job/90007149348"
        )) == 90_007_149_348)
    }

    /// **Nejcennější test téhle sady.** `…/runs/<runId>` končí taky číslem, ale je to **běh**, ne
    /// job — a log běhu je log všech jeho jobů (u změřeného PR 23), tedy přesně to, co se stahovat
    /// nemá. Ověřeno na skutečném odkazu CodeQL, který `/job/` nemá.
    @Test("Číslo běhu se za job ID nevydává")
    func doesNotMistakeARunForAJob() {
        #expect(Policy.jobID(from: url("https://github.com/cli/cli/runs/92918586381")) == nil)
        #expect(Policy.jobID(from: url("https://github.com/cli/cli/actions/runs/30274771802")) == nil)
    }

    /// Odkaz mimo GitHub — bors. Detail se u takového checku **nenabízí**.
    @Test("Odkaz mimo GitHub job ID nedá")
    func ignoresLinksOutsideGitHub() {
        #expect(Policy.jobID(from: url("https://bors.rust-lang.org")) == nil)
        #expect(Policy.jobID(from: url("https://buildkite.com/org/pipe/builds/12345")) == nil)
    }

    @Test("Bez odkazu a s nečíselným jobem je to nil")
    func handlesMissingAndMalformedLinks() {
        #expect(Policy.jobID(from: nil) == nil)
        #expect(Policy.jobID(from: url("https://github.com/o/r/actions/runs/1/job/abc")) == nil)
        #expect(Policy.jobID(from: url("https://github.com/o/r/actions/runs/1/job")) == nil)
    }

    /// Model si číslo bere sám z `link`u, takže se to musí potkat i tam — jinak by se detail
    /// nabízel podle jedné cesty a stahoval podle druhé.
    @Test("Check si job ID odvodí z odkazu")
    func checkExposesTheJobID() {
        let check = PullRequestCheck(
            name: "Tests (aws)",
            outcome: .failed,
            link: url("https://github.com/o/r/actions/runs/1/job/42"),
            startedAt: nil,
            completedAt: nil
        )
        let bors = PullRequestCheck(
            name: "bors",
            outcome: .failed,
            link: url("https://bors.rust-lang.org"),
            startedAt: nil,
            completedAt: nil
        )

        #expect(check.jobID == 42)
        #expect(bors.jobID == nil)
    }

    // MARK: - ANSI

    /// V obou změřených logách ANSI je (116 řádků v 8,78MB logu, 73 v malém) — bez toho se v okně
    /// objeví `^[[36;1m` uprostřed věty.
    @Test("ANSI sekvence se strhnou, text zůstane")
    func stripsANSI() {
        #expect(Policy.strippingANSI("\u{1B}[36;1mPHPUnit\u{1B}[0m 11.5") == "PHPUnit 11.5")
        #expect(Policy.strippingANSI("\u{1B}[0;31mFAIL\u{1B}[0m") == "FAIL")
        #expect(Policy.strippingANSI("bez sekvencí") == "bez sekvencí")
    }

    /// Rozbitá sekvence **nesmí sežrat zbytek logu** — proto se OSC zastaví i na konci řádku.
    @Test("Neuzavřená sekvence nespolkne zbytek")
    func doesNotSwallowTheRestOnBrokenSequences() {
        let stripped = Policy.strippingANSI("\u{1B}]0;titulek\nDruhý řádek")

        #expect(stripped.contains("Druhý řádek"))
    }

    @Test("Odřádkování ani prázdné řádky ANSI čistka nemění")
    func keepsLineStructure() {
        #expect(Policy.strippingANSI("a\n\nb") == "a\n\nb")
    }

    // MARK: - Timestampy

    /// Timestamp má **skoro každý řádek** (změřeno: 25 528 z 25 534) a zabírá 28 znaků, tedy
    /// ukrajuje šířku zrovna tam, kde je potřeba přečíst konec assertace.
    @Test("Timestamp na začátku řádku se sundá")
    func stripsTimestamps() {
        let raw = "2026-08-11T16:09:11.2636913Z  * [new ref] abc -> origin/x"

        #expect(Policy.strippingTimestamps(raw) == " * [new ref] abc -> origin/x")
    }

    /// Ořezává se **tvar, ne pevný počet znaků**: počet desetinných míst se u GitHubu liší.
    @Test("Různě dlouhý zlomek sekundy se pozná taky")
    func stripsTimestampsOfVaryingPrecision() {
        #expect(Policy.strippingTimestamps("2026-08-11T16:09:11.26Z text") == "text")
        #expect(Policy.strippingTimestamps("2026-08-11T16:09:11Z text") == "text")
    }

    /// Co timestamp není, musí zůstat — jinak by čistka ukusovala první slovo řádku.
    @Test("Obyčejné první slovo zůstává")
    func keepsNonTimestamps() {
        #expect(Policy.strippingTimestamps("PHPUnit 11.5 by Sebastian") == "PHPUnit 11.5 by Sebastian")
        #expect(Policy.strippingTimestamps("[ERROR] Found 2 errors") == "[ERROR] Found 2 errors")
        #expect(Policy.strippingTimestamps("") == "")
    }

    // MARK: - Ořez od konce

    /// **Ořezává se od konce a řekne se, kolik se nevešlo.** To, co člověk hledá (selhaná
    /// assertace, stack trace, exit code), je vždycky dole.
    @Test("Bere se konec logu a počítá se, co se nevešlo")
    func takesTheTail() {
        let raw = (1...1_000).map { "řádek \($0)" }.joined(separator: "\n")

        let tail = Policy.logTail(raw, lines: 300)

        #expect(tail.omittedLines == 700)
        #expect(tail.isTruncated)
        #expect(tail.text.hasSuffix("řádek 1000"))
        #expect(tail.text.hasPrefix("řádek 701"))
        #expect(tail.text.split(separator: "\n").count == 300)
    }

    /// Krátký log se **neořezává a netvrdí ořez** — hlavička o vynechaných řádcích u celého logu
    /// je lež.
    @Test("Krátký log zůstane celý a bez hlášky")
    func keepsShortLogsWhole() {
        let tail = Policy.logTail("a\nb\nc", lines: 300)

        #expect(tail.omittedLines == 0)
        #expect(!tail.isTruncated)
        #expect(tail.text == "a\nb\nc")
        #expect(Policy.logTailNotice(tail) == nil)
    }

    /// Koncové `\n` **není řádek logu**: kdyby se počítalo, tvrdil by ořez log, který se do stropu
    /// vešel přesně.
    @Test("Koncové odřádkování se nepočítá jako řádek")
    func ignoresTheTrailingNewline() {
        let raw = (1...300).map { "řádek \($0)" }.joined(separator: "\n") + "\n"

        #expect(Policy.logTail(raw, lines: 300).omittedLines == 0)
    }

    /// Ořez jde **po** čistce, ne před ní — jinak by se do počtu vešly řádky, které se nekreslí.
    @Test("Ocas je už bez ANSI a bez timestampů")
    func tailIsAlreadyClean() {
        let raw = "2026-08-11T16:09:11.2636913Z \u{1B}[31mFAIL\u{1B}[0m"

        #expect(Policy.logTail(raw).text == "FAIL")
    }

    /// Skloňuje se, protože „starších 1 řádků“ je vidět na první pohled. **Čtyřciferný počet se
    /// porovnává po částech**, ne celou větou: `Plural.czech` číslo formátuje podle locale a tisíce
    /// dělí **nezlomitelnou** mezerou, takže napsaná `3 812` s obyčejnou mezerou je červená —
    /// a test by přitom tvrdil něco o formátování čísel, ne o téhle větě.
    @Test("Hláška o vynechaných řádcích se skloňuje")
    func noticeIsDeclined() {
        #expect(Policy.logTailNotice(LogTail(text: "", omittedLines: 1, lineCount: 0)) == "— starších 1 řádek se nevešlo —")
        #expect(Policy.logTailNotice(LogTail(text: "", omittedLines: 3, lineCount: 0)) == "— starších 3 řádky se nevešlo —")

        let many = try? #require(Policy.logTailNotice(LogTail(text: "", omittedLines: 3_812, lineCount: 0)))
        #expect(many?.hasPrefix("— starších ") == true)
        #expect(many?.hasSuffix(" řádků se nevešlo —") == true)
        #expect(many?.contains("812") == true)
    }

    // MARK: - Strop

    /// Strop je **změřený, ne odhadnutý** (#275): dvoumegový ocas skutečného logu se v `NSTextView`
    /// nasází za 220 ms, celých 8,78 MB za 850 ms — 2 MB tedy má rezervu.
    @Test("Do deseti megabajtů se log stahuje")
    func fetchesUpToTheLimit() {
        #expect(Policy.logAvailability(bytes: 1_024) == .fetchable)
        #expect(Policy.logAvailability(bytes: 237_000) == .fetchable, "změřený malý log")
        // **Největší log na našich repech se od #292 vejde.** Do té doby byl 4× nad stropem,
        // a přitom se v sheetu otevře za 6,20 ms — 850 ms z #214 měřilo vynucenou sazbu, kterou
        // aplikace nedělá.
        #expect(Policy.logAvailability(bytes: 8_777_952) == .fetchable, "změřený největší log")
        #expect(Policy.logAvailability(bytes: Policy.logSizeLimit) == .fetchable)
    }

    /// Nad stropem se **nestahuje vůbec** a věta nese **konkrétní velikost** — je z `Content-Length`,
    /// takže to není odhad.
    @Test("Nad stropem se log nestahuje a řekne se, jak je velký")
    func refusesTooLargeLogs() throws {
        guard case .tooLarge(let reason) = Policy.logAvailability(bytes: 12_000_000) else {
            Issue.record("dvanáctimegový log má být nad stropem")
            return
        }

        #expect(reason.contains("12"), "věta má nést konkrétní velikost, ne jen „moc velký“")
        #expect(reason.contains("MB"))
    }

    /// Hodnoty stropů jsou **změřená rozhodnutí**, ne náhoda, takže se tvrdí přímo — kdo je změní,
    /// má u toho projít i důvody v dokumentaci té konstanty.
    @Test("Stropy jsou tam, kde je měření nechalo")
    func limitsAreWhereMeasurementLeftThem() {
        #expect(Policy.logSizeLimit == 10 * 1024 * 1024)
        #expect(Policy.logAvailability(bytes: Policy.logSizeLimit + 1) != .fetchable)
        #expect(Policy.logTailLines == 2_000)
    }

    // MARK: - Věta, dokud se stahuje

    /// **Velikost se slíbí, jen když je známá** (#292). Se stropem na 10 MB se čeká vteřiny až
    /// desítky vteřin, takže mlčící spinner vypadá jako zamrznutí — ale odhad by tvrdil víc, než
    /// data unesou.
    @Test("Hláška o stahování nese velikost, když ji známe")
    func downloadNoticeCarriesTheSize() throws {
        let known = Policy.logDownloadNotice(bytes: 8_777_952)

        #expect(known.contains("8"), "věta má nést konkrétní velikost")
        #expect(known.contains("MB"))
        #expect(known.hasSuffix("…"))
    }

    @Test("Bez známé velikosti hláška nic neslibuje")
    func downloadNoticeSaysNothingWithoutTheSize() {
        let unknown = Policy.logDownloadNotice(bytes: nil)

        #expect(unknown == "Stahuji konec logu…")
        #expect(!unknown.contains("MB"))
        #expect(!unknown.contains("0"))
    }

    // MARK: - Počet řádků ocasu

    /// `lineCount` nese ocas s sebou, protože **z něj se počítá výška okýnka při každém
    /// překreslení** (#292) — scan megabajtového textu v `body` je to, co #224 zakazuje. Musí tedy
    /// odpovídat textu, jinak by okýnko mělo jinou výšku, než kolik je v něm řádků.
    @Test("Počet řádků odpovídá textu")
    func lineCountMatchesTheText() {
        let short = Policy.logTail("a\nb\nc", lines: 300)
        #expect(short.lineCount == 3)
        #expect(short.lineCount == Policy.logLines(of: short.text).count)

        let long = Policy.logTail((1...1_000).map(String.init).joined(separator: "\n"), lines: 300)
        #expect(long.lineCount == 300)
        #expect(long.lineCount == Policy.logLines(of: long.text).count)
    }

    // MARK: - Zakončení řádků

    /// Log z Windows runneru má `CRLF`, a `"\r\n"` je ve Swiftu **jeden `Character`** — takže
    /// `split(separator: "\n")` na něm nerozdělí a z celého logu je jediný řádek. Konec logu by pak
    /// byl celý log a věta „nevešlo se“ by mlčela. Je to tatáž past, na které u #292 skončil rozbor
    /// hlaviček `gh -i`.
    @Test("Log s CRLF se pořeže po řádcích, ne vcelku")
    func cutsLogsWithWindowsLineEndings() {
        let raw = (1...400).map { "řádek \($0)" }.joined(separator: "\r\n")

        // Strop se předává **výslovně**: tenhle test je o zakončení řádků, ne o hodnotě konstanty,
        // takže se nemá rozbít, když se `logTailLines` pohne (a u #292 se pohnul).
        let tail = Policy.logTail(raw, lines: 300)

        #expect(Policy.logLines(of: tail.text).count == 300)
        #expect(tail.lineCount == 300)
        #expect(tail.omittedLines == 100)
        #expect(tail.text.hasSuffix("řádek 400"))
        // Zakončení se přitom **znormalizuje**: v ocasu už `CR` nezbyde. Jinak by ho `NSTextView`
        // sázel jako další zlom a počet ukázaných řádků by se rozešel s tím, co se napočítalo.
        #expect(!tail.text.contains("\r"))
    }

    /// Samotné `CR` (progress bary v CI) je taky zlom řádku — jeden desetitisícový řádek se v okně
    /// nepřečte a z ocasu by byla nudle na vodorovném scrollu.
    @Test("Samotné CR je taky konec řádku")
    func treatsBareCarriageReturnAsALineBreak() {
        #expect(Policy.logLines(of: "a\rb\nc").count == 3)
    }

    /// A timestampy se musí sundat i z `CRLF` logu — jinak by je „schování“ minulo úplně stejně
    /// jako ořez.
    @Test("Timestampy se sundají i z logu s CRLF")
    func stripsTimestampsFromWindowsLineEndings() {
        let raw = "2026-08-11T16:09:11.2636913Z první\r\n2026-08-11T16:09:12.0000000Z druhý\r\n"

        #expect(Policy.strippingTimestamps(raw) == "první\ndruhý\n")
    }
}
