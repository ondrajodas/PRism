import Foundation
import Testing

@testable import PRism

/// Hledání v paletě ⌘K (#184).
///
/// Nejcennější tvrzení jsou tři: **pořadí skupin je pevné** (nálezy první, protože to je jediná
/// věc, kterou aplikace má a prohlížeč ne), **strop je na skupinu** (jinak by nálezy vytlačily
/// všechno ostatní) a **pořadí uvnitř skupiny se nemíchá** (Swiftové `sorted` není stabilní, takže
/// bez druhého kritéria by řádky mezi stisky klávesy poskakovaly).
///
/// Od #336 k tomu čtvrté: **vlastní PR jsou vlastní skupina**, takže mají **svých šest** — na tom
/// stojí to, proč se rozdělovaly.
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
                item("moje PR", group: .myPullRequests),
                item("pull request", group: .pullRequests),
                item("soubor", group: .files),
                item("nález", group: .findings),
            ],
            query: ""
        )

        // Vlastní PR jsou **za** cizími (#336): cizí PR jsou to, na co se čeká.
        #expect(sections.map(\.group) == [.findings, .files, .pullRequests, .myPullRequests, .actions])
        #expect(sections.allSatisfy { $0.hits.count == 1 })
    }

    /// Nadpisy jsou tvrzení, ne kosmetika: se dvěma skupinami PR musí první říct, čeho se týká.
    @Test("Nadpisy skupin: cizí PR jsou „k review“, vlastní „Moje PR“")
    func groupTitlesSayWhichPullRequestsTheyMean() {
        #expect(CommandPalette.Group.pullRequests.title == "Pull requesty k review")
        #expect(CommandPalette.Group.myPullRequests.title == "Moje PR")
    }

    /// **Tohle je ten test, kvůli kterému se skupiny dělily** (#336): ve společné skupině by
    /// dvacet cizích PR vlastní PR vytlačilo, protože šestý řádek je strop.
    @Test("Dvacet cizích PR nevytlačí ani jedno moje")
    func foreignPullRequestsCannotPushOutMyOwn() {
        let theirs = (1...20).map { item("token \($0)", group: .pullRequests, id: "t\($0)") }
        let mine = item("token v mém PR", group: .myPullRequests, id: "mine")

        let sections = Policy.paletteResults(of: theirs + [mine], query: "token", limit: 6)

        #expect(sections.map(\.group) == [.pullRequests, .myPullRequests])
        #expect(sections.first?.hits.count == 6)
        #expect(sections.last?.hits.map(\.id) == ["mine"])
    }

    /// Kdo vlastní PR nemá, nesmí vidět prázdný nadpis — vypadá to jako rozbité hledání.
    @Test("Bez vlastních PR se nadpis „Moje PR“ nekreslí")
    func theOwnGroupDisappearsWithoutOwnPullRequests() {
        let sections = Policy.paletteResults(
            of: [item("fix: token", group: .pullRequests, id: "theirs")],
            query: ""
        )

        #expect(sections.map(\.group) == [.pullRequests])
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

    /// Co je v titulku, resp. v podtitulku **tučně** — text vyříznutý tím rozsahem, který hledání
    /// vrátilo. Přes zkratku, aby v testech nebyl `!` nad `subtitle`: rozsahy jsou dva a každý
    /// platí nad svým řetězcem, takže se nesmí zaměnit.
    private func highlighted(inTitle hit: CommandPalette.Hit) -> String? {
        hit.titleHighlight.map { String(hit.item.title[$0]) }
    }

    private func highlighted(inSubtitle hit: CommandPalette.Hit) -> String? {
        guard let subtitle = hit.item.subtitle, let range = hit.subtitleHighlight else { return nil }
        return String(subtitle[range])
    }

    @Test("Zvýrazní se ten text, ve kterém se to potkalo")
    func highlightPointsWhereTheMatchHappened() throws {
        // Zvýraznit něco v titulku, když se to potkalo v podtitulku, by bylo tvrzení, že se to
        // potkalo tam — a nezvýraznit nic by z řádku udělalo výsledek, u kterého není poznat proč.
        let inTitle = item("src/Vault/SecretClient.php", group: .files, id: "title")
        let inSubtitle = item("nález", subtitle: "SecretClient.php:81", id: "subtitle")

        let hits = Policy.paletteResults(of: [inTitle, inSubtitle], query: "secret")
            .flatMap(\.hits)

        let fromTitle = try #require(hits.first { $0.id == "title" })
        #expect(highlighted(inTitle: fromTitle) == "Secret")
        #expect(highlighted(inSubtitle: fromTitle) == nil)

        let fromSubtitle = try #require(hits.first { $0.id == "subtitle" })
        #expect(highlighted(inTitle: fromSubtitle) == nil)
        #expect(highlighted(inSubtitle: fromSubtitle) == "Secret")
    }

    @Test("Zvýrazní se první slovo, které se potkalo — v každém textu zvlášť")
    func highlightUsesTheFirstMatchingTokenInEachText() throws {
        // `vault client` má zvýraznit repo v podtitulku i slovo v titulku: obojí je důvod, proč
        // řádek vyšel, a každý je vidět jinde.
        let hits = Policy.paletteResults(
            of: [item("SecretClient v souboru", subtitle: "vault#85 · kdosi")],
            query: "vault client"
        ).flatMap(\.hits)
        let found = try #require(hits.first)

        #expect(highlighted(inTitle: found) == "Client")
        #expect(highlighted(inSubtitle: found) == "vault")
    }

    // MARK: - Autor a repozitář (#184, po připomínce)

    @Test("Shoda jen v autorovi řádek najde")
    func matchInTheAuthorAlone() throws {
        // Autor bydlí v podtitulku PR řádku, takže dotaz na jméno musí PR vytáhnout — a shoda
        // musí být vidět zrovna tam, kde to jméno je.
        let pr = item("fix: nezahazovat token", group: .pullRequests, subtitle: "connection#21663 · sykora-ji")

        let hits = Policy.paletteResults(of: [pr], query: "sykora").flatMap(\.hits)
        let found = try #require(hits.first)

        #expect(highlighted(inTitle: found) == nil)
        #expect(highlighted(inSubtitle: found) == "sykora")
    }

    @Test("Shoda jen v repozitáři řádek najde")
    func matchInTheRepositoryAlone() throws {
        // Repo je v podtitulku u nálezu i u PR, takže dotaz na jeho jméno musí zabrat na obojí.
        let finding = item("schází secret", subtitle: "vault#85 · SecretClient.php:81")

        let hits = Policy.paletteResults(of: [finding], query: "vault").flatMap(\.hits)
        let found = try #require(hits.first)

        #expect(highlighted(inSubtitle: found) == "vault")
    }

    @Test("Repozitář a autor naráz platí jako a zároveň")
    func matchInBothRepositoryAndAuthor() {
        // Dvě slova z jednoho podtitulku se musí potkat obě — jinak by `vault sykora` vytáhlo
        // i PR toho autora v jiném repu.
        let mine = item("fix: token", group: .pullRequests, subtitle: "vault#85 · sykora-ji", id: "mine")
        let elsewhere = item("fix: token", group: .pullRequests, subtitle: "connection#21663 · sykora-ji", id: "elsewhere")

        let hits = Policy.paletteResults(of: [mine, elsewhere], query: "vault sykora").flatMap(\.hits)

        #expect(hits.map(\.id) == ["mine"])
    }

    @Test("Shoda v titulku jde před shodou v autorovi i v repu")
    func titleBeatsAuthorAndRepository() {
        // Kdyby to bylo naopak, dotaz na slovo z titulku by vytáhl nahoru cizí PR od stejně
        // pojmenovaného autora — tedy PR, ve kterém to slovo není nikde vidět.
        let byName = item("fix: nezahazovat token", group: .pullRequests, subtitle: "connection#21663 · vault-bot", id: "author")
        let byRepo = item("fix: přepsat log", group: .pullRequests, subtitle: "vault#85 · kdosi", id: "repo")
        let inTitle = item("feat: vault umí rotovat", group: .pullRequests, subtitle: "connection#21664 · kdosi", id: "title")

        let hits = Policy.paletteResults(of: [byName, byRepo, inTitle], query: "vault").flatMap(\.hits)

        // Titulek první; mezi autorem a repem rozhoduje pořadí katalogu, protože podtitulek má
        // jednu váhu — je to výčet dvou souřadnic, ne věta, kde by začátek něco znamenal.
        //
        // **Ověřeno vložením regrese**: když podtitulek dostane váhu titulku, tenhle test padá
        // s pořadím `["author", "repo", "title"]`.
        #expect(hits.map(\.id) == ["title", "author", "repo"])
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

    @Test("„Znovu“ se píše jen tam, kde už jeden běh leží")
    func rerunSaysSoOnlyWithARecord() {
        // Rozhoduje **uložený záznam**, ne to, jestli v něm jsou nálezy: doběhlé review bez nálezů
        // je pořád běh, který se dalším spuštěním přepíše.
        let pr = PRIdentifier("keboola/vault#85")!

        #expect(
            Policy.paletteActions(open: pr, hasRun: true).map(\.title)
                .contains("Pustit review znovu na vault#85")
        )
        #expect(
            Policy.paletteActions(open: pr).map(\.title)
                .contains("Pustit review na vault#85")
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

    /// V tabech, kde panel není vůbec (#294), se položka **nenabízí**: „složit panel“ by slibovalo
    /// něco, co se nemá kde stát, a nešlo by to poznat. `nil` proto není totéž jako `false` —
    /// složený panel v okně **je**, jen jako proužek na hraně.
    @Test("Bez panelu v tabu se položka nenabízí vůbec")
    func reviewPanelActionIsOmittedWithoutThePanel() {
        let pr = PRIdentifier("keboola/vault#85")!

        let items = Policy.paletteActions(open: pr, isPanelExpanded: nil)

        #expect(!items.contains { $0.title.hasSuffix("panel s mým review") })
        #expect(!items.contains { $0.target == .action(.setReviewPanel(expanded: true)) })
        #expect(!items.contains { $0.target == .action(.setReviewPanel(expanded: false)) })
        // Ostatní akce nad PR zůstávají — vypadla jedna položka, ne celá skupina.
        #expect(items.contains { $0.target == .action(.runReview(pr)) })
        #expect(items.contains { $0.target == .action(.setDiffLayout(.split)) })
    }

    /// Sekce se staví z `RailSection.allCases`, takže nová se do palety dostane sama (#331) —
    /// dopsat se musí jedině **tvar jejího jména**. Bez toho by v ní stálo „Otevřít Moje PR“,
    /// tedy nadpis nalepený do věty; a je to ta chyba, která by se udělala nejsnáz.
    @Test("Paleta umí skočit na Moje PR, a ve čtvrtém pádě")
    func offersTheOwnPullRequestsSection() {
        let items = Policy.paletteActions(open: nil, section: .overview)

        #expect(items.contains { $0.target == .action(.openSection(.mine)) })
        #expect(items.map(\.title).contains("Otevřít moje pull requesty"))
        // Každá sekce kromě té viditelné má řádek — počet drží i test o vzhledu v `SidebarRailTests`.
        let sections = items.compactMap { item -> RailSection? in
            guard case .action(.openSection(let section)) = item.target else { return nil }
            return section
        }
        #expect(Set(sections) == Set(RailSection.allCases).subtracting([.overview]))
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
