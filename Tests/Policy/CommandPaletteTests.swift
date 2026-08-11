import Foundation
import Testing

@testable import PRism

/// Hledání v paletě ⌘K (#184).
///
/// Nejcennější tvrzení jsou tři: **pořadí skupin je pevné** (nálezy první, protože to je jediná
/// věc, kterou aplikace má a prohlížeč ne), **strop je na skupinu** (jinak by nálezy vytlačily
/// všechno ostatní) a **pořadí uvnitř skupiny se nemíchá** (Swiftové `sorted` není stabilní, takže
/// bez druhého kritéria by řádky mezi stisky klávesy poskakovaly).
@Suite("Policy — command palette")
struct CommandPaletteTests {
    private func item(
        _ title: String,
        group: CommandPalette.Group = .findings,
        subtitle: String? = nil,
        keywords: [String] = [],
        id: String? = nil
    ) -> CommandPalette.Item {
        CommandPalette.Item(
            id: id ?? "\(group)-\(title)",
            group: group,
            title: title,
            subtitle: subtitle,
            mark: .finding,
            keywords: keywords,
            target: .action(.refresh)
        )
    }

    // MARK: - Skupiny

    @Test("Prázdný dotaz ukáže všechny skupiny v pevném pořadí")
    func emptyQueryShowsEverything() {
        // Paleta se otevírá jako nabídka toho, co je po ruce — prázdné okno by z ⌘K udělalo
        // krok navíc. Pořadí skupin je tvrzení o tom, k čemu je okno.
        let sections = Policy.paletteResults(
            of: [
                item("akce", group: .actions),
                item("pull request", group: .pullRequests),
                item("soubor", group: .files),
                item("nález", group: .findings),
            ],
            query: ""
        )

        #expect(sections.map(\.group) == [.findings, .files, .pullRequests, .actions])
        #expect(sections.allSatisfy { $0.hits.count == 1 })
    }

    @Test("Skupina bez shody vypadne celá")
    func groupsWithoutHitsDisappear() {
        // Nadpis nad prázdnem by tvrdil, že se hledalo a nic není.
        let sections = Policy.paletteResults(
            of: [item("secret", group: .findings), item("token", group: .files)],
            query: "secret"
        )

        #expect(sections.map(\.group) == [.findings])
    }

    @Test("Strop platí na skupinu, ne na celek")
    func limitAppliesPerGroup() {
        // Dvacet nálezů nesmí vytlačit soubory, PR ani akce — jinak přestane být paleta jedno
        // pole na všechno.
        let findings = (1...20).map { item("nález \($0)", group: .findings, id: "f\($0)") }
        let sections = Policy.paletteResults(
            of: findings + [item("akce", group: .actions)],
            query: "",
            limit: 6
        )

        #expect(sections.first?.hits.count == 6)
        #expect(sections.last?.group == .actions)
        #expect(sections.last?.hits.count == 1)
    }

    @Test("Nic nesedí = žádná skupina")
    func nothingMatchesGivesNoSections() {
        #expect(Policy.paletteResults(of: [item("secret")], query: "xyzzy").isEmpty)
    }

    // MARK: - Váhy

    @Test("Titulek váží víc než podtitulek a ten víc než klíčové slovo")
    func titleBeatsSubtitleBeatsKeyword() {
        let sections = Policy.paletteResults(
            of: [
                item("nález s klíčovým slovem", keywords: ["vault"], id: "keyword"),
                item("nález s podtitulkem", subtitle: "vault#85", id: "subtitle"),
                item("vault se rozbil", id: "title"),
            ],
            query: "vault"
        )

        #expect(sections.first?.hits.map(\.id) == ["title", "subtitle", "keyword"])
    }

    @Test("Začátek titulku váží víc než hranice slova a ta víc než vnitřek")
    func prefixBeatsWordStartBeatsSubstring() {
        // U cest k souborům to rozhoduje: `secret` v `src/Vault/SecretClient.php` znamená víc
        // než v `MySecretThing.php`.
        let sections = Policy.paletteResults(
            of: [
                item("MySecretThing.php", group: .files, id: "inside"),
                item("src/Vault/SecretClient.php", group: .files, id: "word"),
                item("SecretClient.php", group: .files, id: "prefix"),
            ],
            query: "secret"
        )

        #expect(sections.first?.hits.map(\.id) == ["prefix", "word", "inside"])
    }

    @Test("Pořadí katalogu se při shodných váhách nemíchá")
    func equalRanksKeepCatalogOrder() {
        // `sorted` v Swiftu **nemá stabilitu v kontraktu**, i když ji dnešní implementace
        // (timsort) drží — proto se pořadí katalogu nese v klíči řazení výslovně.
        //
        // **Vloženou regresí tenhle test nepadá** (zkoušeno: bez druhého kritéria a se 40 prvky
        // projde), takže nedokazuje pravidlo, jen ho drží zapsané. Kdyby se stabilita v nějaké
        // verze Swiftu ztratila, poskakovaly by řádky pod rukou a chytilo by se to tady.
        let items = (1...40).map { item("nález \($0)", id: "f\($0)") }

        let hits = Policy.paletteResults(of: items, query: "nález", limit: 40).first?.hits ?? []

        #expect(hits.map(\.id) == items.map(\.id))
    }

    // MARK: - Co je shoda

    @Test("Hledá se bez ohledu na diakritiku a velikost písmen")
    func searchIgnoresCaseAndDiacritics() {
        // Aplikace je česká: `nalez` musí najít `nález`, jinak by se paleta dala používat jen
        // s přepnutou klávesnicí.
        let items = [item("Nález v šifrování")]

        #expect(!Policy.paletteResults(of: items, query: "nalez").isEmpty)
        #expect(!Policy.paletteResults(of: items, query: "SIFROVANI").isEmpty)
    }

    @Test("Víc slov znamená a zároveň")
    func multipleTokensMustAllMatch() {
        // `vault secret` má najít nález ve `vaultu`, i když ta dvě slova v textu vedle sebe
        // nestojí — a nesmí najít nález z jiného repa.
        let items = [
            item("schází secret", subtitle: "vault#85", id: "vault"),
            item("schází secret", subtitle: "connection#21663", id: "connection"),
        ]

        let hits = Policy.paletteResults(of: items, query: "vault secret").first?.hits ?? []

        #expect(hits.map(\.id) == ["vault"])
    }

    @Test("Zvýrazňuje se shoda v titulku, jinde nic")
    func highlightPointsIntoTheTitle() {
        // Zvýraznit něco v titulku, když se to potkalo v podtitulku, by bylo tvrzení, že se to
        // potkalo tam.
        let inTitle = item("src/Vault/SecretClient.php", group: .files, id: "title")
        let elsewhere = item("nález", subtitle: "SecretClient.php:81", id: "subtitle")

        let hits = Policy.paletteResults(of: [inTitle, elsewhere], query: "secret")
            .flatMap(\.hits)

        let highlighted = hits.first { $0.id == "title" }
        #expect(highlighted?.highlight.map { String(inTitle.title[$0]) } == "Secret")
        #expect(hits.first { $0.id == "subtitle" }?.highlight == nil)
    }

    @Test("Zvýrazní se první slovo, které se potkalo v titulku")
    func highlightUsesTheFirstMatchingToken() {
        let hit = Policy.paletteResults(
            of: [item("SecretClient v souboru", subtitle: "vault#85")],
            query: "vault client"
        ).first?.hits.first

        #expect(hit?.highlight.map { String(hit!.item.title[$0]) } == "Client")
    }

    // MARK: - Akce

    @Test("Bez otevřeného PR se nenabízí nic, co na PR visí")
    func actionsWithoutAnOpenPullRequest() {
        // Řádek, který by nic neudělal, se nenabízí — tatáž zásada jako u bloku `Co teď`.
        let titles = Policy.paletteActions(open: nil).map(\.title)

        #expect(!titles.contains { $0.contains("review na") })
        #expect(!titles.contains { $0.contains("diff") })
        #expect(!titles.contains { $0.contains("panel") })
        #expect(titles.contains("Otevřít nastavení"))
        #expect(titles.contains("Obnovit seznam pull requestů"))
    }

    @Test("Nad otevřeným PR se review pouští, za běhu ruší")
    func runningReviewSwapsTheAction() {
        let pr = PRIdentifier("keboola/vault#85")!

        let idle = Policy.paletteActions(open: pr).map(\.title)
        let running = Policy.paletteActions(open: pr, isReviewing: true).map(\.title)

        #expect(idle.contains("Pustit review na vault#85"))
        #expect(!idle.contains { $0.hasPrefix("Zrušit") })
        #expect(running.contains("Zrušit běžící review na vault#85"))
        #expect(!running.contains { $0.hasPrefix("Pustit") })
    }

    @Test("„Znovu“ se píše jen tam, kde už nálezy leží")
    func rerunSaysSoOnlyWithARecord() {
        let pr = PRIdentifier("keboola/vault#85")!

        #expect(
            Policy.paletteActions(open: pr, hasFindings: true).map(\.title)
                .contains("Pustit review znovu na vault#85")
        )
    }

    @Test("Pohled na diff nabízí ten druhý")
    func diffLayoutOffersTheOtherView() {
        // Text tlačítka je to, co se stane — ne to, ve kterém pohledu se zrovna je.
        let pr = PRIdentifier("keboola/vault#85")!

        let fromUnified = Policy.paletteActions(open: pr, layout: .unified)
        let fromSplit = Policy.paletteActions(open: pr, layout: .split)

        #expect(fromUnified.contains { $0.title == "Přepnout diff na „vedle sebe“" })
        #expect(fromSplit.contains { $0.title == "Přepnout diff na „pod sebou“" })
        #expect(fromUnified.contains { $0.target == .action(.setDiffLayout(.split)) })
        #expect(fromSplit.contains { $0.target == .action(.setDiffLayout(.unified)) })
    }

    @Test("Panel se nabízí složit, když je rozložený, a naopak")
    func reviewPanelActionFollowsItsState() {
        let pr = PRIdentifier("keboola/vault#85")!

        let expanded = Policy.paletteActions(open: pr, isPanelExpanded: true)
        let collapsed = Policy.paletteActions(open: pr, isPanelExpanded: false)

        #expect(expanded.contains { $0.title == "Složit panel s mým review" })
        #expect(expanded.contains { $0.target == .action(.setReviewPanel(expanded: false)) })
        #expect(collapsed.contains { $0.title == "Rozložit panel s mým review" })
        // Zkratka se kreslí jen tam, kde doopravdy funguje — `⌘2` registruje detail PR.
        #expect(expanded.first { $0.title.hasSuffix("panel s mým review") }?.shortcut == "⌘2")
    }

    @Test("Viditelná sekce railu se v domácí záložce nenabízí, nad PR ano")
    func visibleSectionIsOfferedOnlyWhenItWouldChangeSomething() {
        let home = Policy.paletteActions(open: nil, section: .queue).map(\.title)
        let overPullRequest = Policy.paletteActions(open: PRIdentifier("keboola/vault#85")!, section: .queue)
            .map(\.title)

        #expect(!home.contains("Otevřít frontu"))
        #expect(home.contains("Otevřít přehled"))
        // Nad otevřeným PR přepne i záložku, takže udělá něco i pro tu sekci, která je „vidět“.
        #expect(overPullRequest.contains("Otevřít frontu"))
    }

    @Test("Akce nemají kreslenou zkratku, kterou aplikace nemá")
    func actionsOnlyDrawRealShortcuts() {
        // `⌘⇧R` v návrhu patří jiné akci (pustit review na vše, co neběželo, na dashboardu),
        // takže na řádku „pustit review na tenhle PR“ by to byla lež o tom, co okno umí.
        let items = Policy.paletteActions(open: PRIdentifier("keboola/vault#85")!)

        #expect(items.compactMap(\.shortcut).sorted() == ["⌘,", "⌘2"])
    }

    @Test("Akce jsou vždycky ve své skupině a nikam neodesílají")
    func actionsAreActions() {
        // Tvrdá podmínka č. 1: ve výčtu není nic, co by sahalo na `ReviewPublishing`. Kdyby se
        // do palety přidal cíl, který odesílá, tenhle výčet ho musí ukázat.
        let targets = Policy.paletteActions(open: PRIdentifier("keboola/vault#85")!).map(\.target)

        #expect(Policy.paletteActions(open: nil).allSatisfy { $0.group == .actions })
        #expect(targets.allSatisfy { if case .action = $0 { true } else { false } })
    }
}
