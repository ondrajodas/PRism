import Foundation
import Testing

@testable import PRism

/// Slití sady nálezů z jednoho volání `ReportFindings` do toho, co dorazilo dřív (#381).
///
/// Čistá funkce, takže se testuje výčtem — a výčet je tady to podstatné: každý řádek popisuje
/// jednu situaci, ve které se **korekce** a **druhý problém na jednom řádku** rozhodují jinak.
@Suite("Policy.mergedFindings")
struct FindingMergeTests {
    private func merge(
        _ collected: [ReportedFinding],
        _ reported: [ReportedFinding]
    ) -> [ReportedFinding] {
        Policy.mergedFindings(collected, reporting: reported)
    }

    // MARK: - Sada do prázdna

    @Test("Prázdná sada nesmaže, co už dorazilo")
    func anEmptyReportKeepsWhatArrived() {
        // Vypadne to samo z pravidla „přepisuje se podle místa“: prázdná sada nemá místo,
        // ke kterému by mlčení patřilo. Kdyby to bylo naopak, závěrečné volání s prázdným
        // polem by z běhu se třemi nálezy udělalo „čisté review“.
        let collected = [makeReported(file: "A.php", line: 12, summary: "ztráta dat")]

        #expect(merge(collected, []) == collected)
    }

    @Test("Dva nálezy na jednom místě v jedné sadě zůstanou dva")
    func twoFindingsOnOneLineInOneReportStayTwo() {
        // Reviewer je vyjmenoval vedle sebe, takže je to jeho poslední slovo o tom místě:
        // dva problémy. Doložené reálným během — `review-with-findings` má dva nálezy na
        // `Cart.swift:17`. Slití podle `(file, line, category)` by z nich udělalo jeden.
        let batch = [
            makeReported(file: "Cart.swift", line: 17, category: "input-validation", summary: "sleva bez mezí"),
            makeReported(file: "Cart.swift", line: 17, category: "rounding", summary: "celočíselné dělení"),
        ]

        #expect(merge([], batch) == batch)
    }

    // MARK: - Korekce

    @Test("Pozdější sada přepíše nález na tomtéž místě")
    func aLaterReportReplacesTheFindingAtTheSamePlace() {
        // Přesně případ z #381: rozdíl je jen v přeformulovaném textu, místo je stejné.
        let draft = makeReported(file: "A.php", line: 346, summary: "přidá entry fáze")
        let corrected = makeReported(file: "A.php", line: 346, summary: "přidá entry fázi")

        #expect(merge([draft], [corrected]) == [corrected])
    }

    @Test("Opravený nález zůstane na svém pořadí")
    func aCorrectedFindingKeepsItsPosition() {
        // Nález, který se jen opravil, nemá v okně poskočit na konec seznamu.
        let first = makeReported(file: "A.php", line: 10, summary: "první")
        let second = makeReported(file: "B.php", line: 20, summary: "druhý")
        let corrected = makeReported(file: "A.php", line: 10, summary: "první, opraveno")

        #expect(merge([first, second], [corrected]) == [corrected, second])
    }

    @Test("Verdikt a kategorie z pozdější sady přebijí náčrt")
    func aLaterReportBringsVerdictAndCategory() {
        // Na `verdict` a `category` stojí blokující příznak — držet se prvního hlášení by
        // z potvrzeného nálezu v blokující kategorii udělalo neblokující.
        let draft = makeReported(file: "A.php", line: 96, category: nil, verdict: nil, summary: "ztráta dat")
        let complete = makeReported(file: "A.php", line: 96, category: "data-loss", verdict: .confirmed, summary: "ztráta dat")

        #expect(merge([draft], [complete]) == [complete])
    }

    // MARK: - Nic se nezahodí potichu

    @Test("Nález, o kterém pozdější sada mlčí, zůstane")
    func aFindingTheLaterReportIsSilentAboutSurvives() {
        // Tichá ztráta nálezu se v okně nedá odlišit od „reviewer nic nenašel“. Nález navíc
        // je naopak vidět a dá se odmítnout (#113), takže se z těch dvou omylů volí ten
        // levnější.
        let forgotten = makeReported(file: "A.php", line: 10, summary: "ztráta dat")
        let fresh = makeReported(file: "B.php", line: 20, summary: "pád na prázdném poli")

        #expect(merge([forgotten], [fresh]) == [forgotten, fresh])
    }

    @Test("Přebytek na tomtéž místě zůstane")
    func theSurplusAtTheSamePlaceSurvives() {
        // Pozdější sada nese na tom místě jednu položku, dřív tam byly dvě: přepíše se
        // tolik, kolik sama nese, zbytek zůstane. Jinak by korekce jednoho ze dvou
        // problémů na řádku ten druhý potichu smazala.
        let first = makeReported(file: "A.php", line: 10, summary: "chybí kontrola")
        let second = makeReported(file: "A.php", line: 10, summary: "celočíselné dělení")
        let corrected = makeReported(file: "A.php", line: 10, summary: "chybí kontrola prázdnosti")

        #expect(merge([first, second], [corrected]) == [corrected, second])
    }

    @Test("Rozdělený nález se rozdělí")
    func aFindingSplitIntoTwoBecomesTwo() {
        // Obráceně: dřív jeden, teď dva na tomtéž místě. První se přepíše, druhý se připojí.
        let original = makeReported(file: "A.php", line: 10, summary: "něco je špatně")
        let batch = [
            makeReported(file: "A.php", line: 10, summary: "chybí kontrola"),
            makeReported(file: "A.php", line: 10, summary: "a k tomu useknutý zbytek"),
        ]

        #expect(merge([original], batch) == batch)
    }

    // MARK: - Nález bez místa

    @Test("Nález bez místa se páruje podle summary")
    func aPlacelessFindingIsMatchedBySummary() {
        // „Stejný soubor bez řádku“ není místo (tatáž úvaha jako u `Policy.groups(of:)`),
        // takže párování podle místa by dvě různé poznámky slilo do jedné. Pro nález bez
        // místa se proto proti stavu do #381 nemění nic.
        let note = makeReported(summary: "chybí testy")
        let other = makeReported(summary: "architektura: dvě cesty k témuž")

        #expect(merge([note], [note]) == [note])
        #expect(merge([note], [other]) == [note, other])
    }

    @Test("Nález bez místa se nespáruje s nálezem na místě")
    func aPlacelessFindingDoesNotMatchAPlacedOne() {
        let note = makeReported(summary: "chybí testy")
        let placed = makeReported(file: "A.php", line: 10, summary: "chybí testy")

        #expect(merge([note], [placed]) == [note, placed])
        #expect(merge([placed], [note]) == [placed, note])
    }

    @Test("Soubor bez řádku není místo")
    func aFileWithoutALineIsNotAPlace() {
        // Kdyby byl, dva nálezy o tomtéž souboru bez řádku by se slily — a `Policy.groups`
        // je přitom drží každý zvlášť.
        let first = makeReported(file: "A.php", summary: "soubor je moc velký")
        let second = makeReported(file: "A.php", summary: "chybí licenční hlavička")

        #expect(merge([first], [second]) == [first, second])
    }
}
