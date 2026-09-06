import Foundation
import Testing

@testable import PRism

/// Dávkový dotaz na odložené pull requesty (#512) — jeden dokument na všechna odložená PR.
///
/// **Nejcennější tvrzení je to o počtu**: tři PR ze tří repozitářů jsou jeden argument `query=`
/// a jedno spuštění `gh`. Kdyby se to rozpadlo na dotaz per PR, byl by z tiku několikanásobek
/// volání — a nikdo by si toho nevšiml, protože výsledek v okně by byl stejný.
@Suite("Dotaz na odložené pull requesty (#512)")
struct SnoozeProbeQueryTests {
    private let ids = [
        PRIdentifier("cli/cli#14252")!,
        PRIdentifier("microsoft/terminal#20580")!,
        PRIdentifier("vercel/next.js#97830")!,
    ]

    /// Odpověď složená inline: skutečný výstup se z veřejného repa sehnat dá, ale nese celé
    /// spojení komentářů — a tady jde o **dvě čísla a jednu sha**, takže by fixture byla z 99 %
    /// materiál, který dotaz vůbec nechce. Tvar je opsaný z odpovědi na `PullRequestHeadsQuery`
    /// (`data.prN.pullRequest`), tedy z formátu, který je fixturou ověřený.
    private func response(_ json: String) throws -> GhSnoozeSignalsResponse {
        try GhOutput.decoder.decode(GhSnoozeSignalsResponse.self, from: Data(json.utf8))
    }
}

// MARK: - Dokument a argumenty

extension SnoozeProbeQueryTests {
    @Test("Tři PR ze tří repozitářů jsou jeden dotaz")
    func buildsASingleQuery() {
        let arguments = SnoozeProbeQuery.arguments(for: ids)

        #expect(arguments.prefix(3) == ["api", "graphql", "-f"])
        #expect(arguments.count { $0.hasPrefix("query=") } == 1)
        let document = arguments.first { $0.hasPrefix("query=") }!
        for index in 0..<3 {
            #expect(document.contains("\(SnoozeProbeQuery.alias(index)): repository("))
        }
        #expect(document.contains("pr3:") == false)
    }

    /// Tatáž past jako u `PullRequestHeadsQuery`: jméno repa je z konfigurace a `number` je
    /// v GraphQL `Int!`, takže `-f` by dotaz položilo na typu.
    @Test("Hodnoty jdou přes -F, ne do dokumentu")
    func passesValuesAsVariables() {
        let arguments = SnoozeProbeQuery.arguments(for: ids)

        #expect(arguments.count { $0 == "-F" } == 9)
        #expect(arguments.contains("owner0=cli"))
        #expect(arguments.contains("number0=14252"))
        #expect(arguments.contains("name2=next.js"))
        #expect(arguments.first { $0.hasPrefix("query=") }!.contains("next.js") == false)
    }

    /// **Součty, ne seznamy**: `totalCount` je jedno číslo bez stránkování, takže se nestahuje ani
    /// jeden komentář. Kdyby se sem někdy dostalo `nodes`, byl by z levného dotazu ten nejdražší
    /// v aplikaci — a poznalo by se to jedině měřením.
    @Test("Dotaz si říká o součty, ne o obsah")
    func asksForCountsOnly() {
        let document = SnoozeProbeQuery.arguments(for: ids).first { $0.hasPrefix("query=") }!

        #expect(document.contains("comments { totalCount }"))
        #expect(document.contains("reviews { totalCount }"))
        #expect(document.contains("headRefOid"))
        #expect(document.contains("nodes") == false)
    }

    /// Push a komentář jsou **dvě různé podmínky**, takže se commity do počtu příspěvků počítat
    /// nesmí — jinak by „do dalšího komentáře“ skončilo pushem.
    @Test("Commity do počtu příspěvků nepatří")
    func neverCountsCommits() {
        let document = SnoozeProbeQuery.arguments(for: ids).first { $0.hasPrefix("query=") }!

        #expect(document.contains("commits") == false)
    }
}

// MARK: - Rozbor odpovědi

extension SnoozeProbeQueryTests {
    @Test("Komentáře a review se sčítají do jednoho čísla")
    func sumsCommentsAndReviews() throws {
        let parsed = try response("""
        {"data": {"pr0": {"pullRequest": {
            "headRefOid": "4f2ac91", "comments": {"totalCount": 3}, "reviews": {"totalCount": 2}
        }}}}
        """)

        let signals = parsed.signals(of: [ids[0]])

        #expect(signals[ids[0]] == SnoozeSignal(head: "4f2ac91", comments: 5))
    }

    /// **Chybějící alias v mapě není.** „Na tuhle PR nevíme“ se od „nezměnilo se nic“ musí poznat,
    /// protože z prvního se nesmí nic tvrdit — a u odložení je to ten rozdíl mezi „trvá dál“
    /// a „vrátit do fronty“. Částečná odpověď je přitom platná odpověď.
    @Test("Nedostupné PR v mapě chybí a zbytek přežije")
    func partialAnswersSurvive() throws {
        let parsed = try response("""
        {"data": {
            "pr0": null,
            "pr1": {"pullRequest": {
                "headRefOid": "9c1de02", "comments": {"totalCount": 1}, "reviews": {"totalCount": 0}
            }}
        }}
        """)

        let signals = parsed.signals(of: [ids[0], ids[1]])

        #expect(signals[ids[0]] == nil)
        #expect(signals[ids[1]]?.head == "9c1de02")
    }

    /// Chybějící spojení je nula, ne „nevíme“: prázdné spojení GitHub posílá s `totalCount: 0`
    /// a nula je u počtu bezpečná strana — `Policy.snoozeBaseline` z ní udělá nejvýš nižší základ.
    @Test("Chybějící spojení se počítá jako nula")
    func missingConnectionsCountAsZero() throws {
        let parsed = try response("""
        {"data": {"pr0": {"pullRequest": {"headRefOid": "4f2ac91"}}}}
        """)

        #expect(parsed.signals(of: [ids[0]])[ids[0]] == SnoozeSignal(head: "4f2ac91", comments: 0))
    }

    /// Odpověď bez `data` je hranice mezi „částečná odpověď“ a „odpověď nedorazila“ — a rozbírá
    /// se až u volajícího, který z ní udělá chybu. Tady jen prázdno, ne pád.
    @Test("Odpověď bez data dá prázdno")
    func missingDataIsEmpty() throws {
        #expect(try response("{}").signals(of: ids).isEmpty)
    }
}
