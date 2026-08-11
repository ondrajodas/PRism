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
        #expect(Policy.logTailNotice(LogTail(text: "", omittedLines: 1)) == "— starších 1 řádek se nevešlo —")
        #expect(Policy.logTailNotice(LogTail(text: "", omittedLines: 3)) == "— starších 3 řádky se nevešlo —")

        let many = try? #require(Policy.logTailNotice(LogTail(text: "", omittedLines: 3_812)))
        #expect(many?.hasPrefix("— starších ") == true)
        #expect(many?.hasSuffix(" řádků se nevešlo —") == true)
        #expect(many?.contains("812") == true)
    }

    // MARK: - Strop

    /// Strop je **změřený, ne odhadnutý** (#275): dvoumegový ocas skutečného logu se v `NSTextView`
    /// nasází za 220 ms, celých 8,78 MB za 850 ms — 2 MB tedy má rezervu.
    @Test("Do dvou megabajtů se log stahuje")
    func fetchesUpToTheLimit() {
        #expect(Policy.logAvailability(bytes: 1_024) == .fetchable)
        #expect(Policy.logAvailability(bytes: 237_000) == .fetchable, "změřený malý log")
        #expect(Policy.logAvailability(bytes: Policy.logSizeLimit) == .fetchable)
    }

    /// Nad stropem se **nestahuje vůbec** a věta nese **konkrétní velikost** — je z `Content-Length`,
    /// takže to není odhad.
    @Test("Nad stropem se log nestahuje a řekne se, jak je velký")
    func refusesTooLargeLogs() throws {
        guard case .tooLarge(let reason) = Policy.logAvailability(bytes: 8_777_952) else {
            Issue.record("osmimegový log má být nad stropem")
            return
        }

        #expect(reason.contains("8"), "věta má nést konkrétní velikost, ne jen „moc velký“")
        #expect(reason.contains("MB"))
    }

    @Test("Strop je zrovna na dvou megabajtech")
    func limitIsTwoMegabytes() {
        #expect(Policy.logSizeLimit == 2 * 1024 * 1024)
        #expect(Policy.logAvailability(bytes: Policy.logSizeLimit + 1) != .fetchable)
    }

    // MARK: - Content-Length z hlaviček

    /// `gh -i` u redirectu vypíše hlavičky **obou** odpovědí a ta první má `Content-Length: 0`.
    /// Kdyby se brala první, vyšel by každý log jako prázdný — a strop by ho pustil bez ohledu
    /// na velikost.
    @Test("Bere se velikost z odpovědi za redirectem, ne nula před ním")
    func readsTheContentLengthBehindTheRedirect() {
        let headers = """
            HTTP/2.0 302 Found
            Content-Length: 0
            Location: https://productionresultssa0.blob.core.windows.net/x

            HTTP/1.1 200 OK
            Content-Length: 8777952
            """

        #expect(GhGateway.contentLength(in: headers) == 8_777_952)
    }

    @Test("Bez Content-Length se velikost nehádá")
    func doesNotGuessWithoutContentLength() {
        #expect(GhGateway.contentLength(in: "HTTP/1.1 200 OK\nContent-Type: text/plain") == nil)
    }
}
