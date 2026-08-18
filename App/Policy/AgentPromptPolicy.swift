import Foundation

/// Jedna sekce zadání — soubor a to, co se v něm řeší (#333).
///
/// `file == nil` je sekce `K celému PR (bez souboru)` a stojí **první**: souhrn review a komentář
/// pod PR se k žádnému řádku nevážou, a zrovna v souhrnu bývá to obecné, kvůli čemu kolega změny
/// vyžádal.
struct AgentPromptSection: Hashable, Sendable, Identifiable {
    let file: String?
    let items: [AgentPromptItem]

    var id: String { file ?? "" }
}

/// Skládání zadání pro agenta (#333). Čisté funkce, žádné I/O — testuje se výčtem bez mockování.
///
/// **Zadání nikam neodchází.** Výsledkem je text, který skončí ve schránce nebo v souboru; nic
/// v tomhle souboru nezná `gh`, `ReviewPublishing` ani `URL` na GitHub API. Tvrdá podmínka č. 1
/// se tím nemění a je na to test (`SingleWayOutTests`).
extension Policy {
    /// Všechno, co aplikace o PR ví a co se dá předat — **bez ohledu na volby**.
    ///
    /// Nefiltruje se tady, protože z téhož seznamu se počítají i čísla u vypnutých voleb: „1
    /// vyřešené vynecháno“ se nedá napsat nad seznamem, ze kterého vyřešené vypadlo už při sběru.
    ///
    /// Vynechává se jedině **prázdná obálka review** — každý řádkový komentář na GitHubu patří do
    /// nějakého review, takže u PR s pěti komentáři u kódu přijde pět review, která nejsou
    /// tvrzením. Tatáž úvaha jako v `Policy.overview`; schválení s prázdným tělem se nezahazuje,
    /// to je plnohodnotný verdikt.
    ///
    /// **Vlastní komentáře se nevyřazují.** Na vlastním PR je vlákno, které jsem si založil sám,
    /// poznámka „tady se ještě musím vrátit“ — tedy práce, ne cizí názor. Autor je u každé položky
    /// v textu napsaný, takže se nedá splést s cizím.
    static func agentPromptItems(
        findings: [Finding],
        dismissals: [FindingKey: FindingDismissal] = [:],
        conversation: Conversation?
    ) -> [AgentPromptItem] {
        let fromFindings = findings.map { finding in
            AgentPromptItem.finding(finding, dismissedAs: dismissals[key(of: finding)]?.reason)
        }
        guard let conversation else { return fromFindings }
        let threads = conversation.threads.items.map { AgentPromptItem.thread($0) }
        let comments = conversation.comments.items.map { AgentPromptItem.comment($0) }
        let reviews = conversation.reviews.items
            .filter { $0.isVerdict || !$0.body.isEmpty }
            .map { AgentPromptItem.review($0) }
        return fromFindings + threads + comments + reviews
    }

    /// Zadání pro agenta — text a počty k němu.
    ///
    /// `diff` je tady jen kvůli hunkům u nálezů: vlákno svůj `diffHunk` nese samo (je to snímek
    /// z commitu, na kterém vzniklo), kdežto u nálezu se musí najít v dnešním diffu. Bez načteného
    /// diffu se hunk prostě nepřiloží — text tím neztrácí položku, jen pohodlí.
    /// - Parameter only: zúžení na vyjmenované položky podle `AgentPromptItem.id` (#334).
    ///   `nil` = neomezovat. Používá to jedině `Sestavit i tak (jen nové vlákno)` po pushi: nálezy
    ///   v tu chvíli platí pro starý kód, takže se předává jen to, co po předání přibylo v diskuzi.
    ///   **Do `inventory` se to nepromítá** — počty u voleb dál mluví o tom, co na PR je, jinak by
    ///   zúžené zadání vypadalo jako celé.
    static func agentPrompt(
        for subject: AgentPromptSubject,
        findings: [Finding],
        dismissals: [FindingKey: FindingDismissal] = [:],
        conversation: Conversation?,
        diff: Diff? = nil,
        blocking: Set<String> = defaultBlockingCategories,
        options: AgentPromptOptions,
        only: Set<String>? = nil
    ) -> AgentPrompt {
        let all = agentPromptItems(findings: findings, dismissals: dismissals, conversation: conversation)
        let included = all.filter { options.includes($0.choice) && (only?.contains($0.id) ?? true) }
        let sections = agentPromptSections(included, blocking: blocking)
        return AgentPrompt(
            subject: subject,
            text: agentPromptText(
                for: subject,
                sections: sections,
                diff: options.includes(.diffHunks) ? diff : nil,
                withHunks: options.includes(.diffHunks),
                blocking: blocking,
                isConversationLoaded: conversation != nil
            ),
            inventory: AgentPromptInventory(all),
            included: AgentPromptInventory(included),
            handed: Set(included.map(\.id)),
            blocking: included.count { isBlockingItem($0, categories: blocking) },
            isConversationLoaded: conversation != nil
        )
    }

    /// Položky rozdělené po souborech — **sekce bez souboru první**, pak soubory.
    ///
    /// Pořadí souborů: nejdřív ty, ve kterých něco **blokuje**, pak abecedně. Je to jediné
    /// pořadí, které se dá odůvodnit i zopakovat: agent otevírá soubor, takže je jedno, ze
    /// kterého revieweera položka přišla, ale není jedno, jestli se v souboru něco láme.
    ///
    /// Uvnitř sekce se řadí podle **řádku**, položky bez řádku první (platí pro celý soubor).
    /// Při shodě rozhoduje `id`, ať je pořadí úplné a nepřeskakuje mezi překresleními.
    static func agentPromptSections(
        _ items: [AgentPromptItem],
        blocking: Set<String> = defaultBlockingCategories
    ) -> [AgentPromptSection] {
        let grouped = Dictionary(grouping: items) { $0.file }
        let whole = grouped[nil].map { [AgentPromptSection(file: nil, items: sortedWholeItems($0))] } ?? []
        let files = grouped
            .compactMap { file, items -> AgentPromptSection? in
                guard let file else { return nil }
                return AgentPromptSection(file: file, items: sortedFileItems(items))
            }
            .sorted { left, right in
                let leftBlocks = left.items.contains { isBlockingItem($0, categories: blocking) }
                let rightBlocks = right.items.contains { isBlockingItem($0, categories: blocking) }
                guard leftBlocks == rightBlocks else { return leftBlocks }
                return (left.file ?? "") < (right.file ?? "")
            }
        return whole + files
    }

    /// Blokuje položka? Jedině nález — u cizího komentáře aplikace závažnost neposuzuje
    /// (`ReportFindings` pole pro ni má, diskuze ne) a hádat ji z textu by znamenalo vymyslet si
    /// vlastní škálu, což tahle aplikace nedělá.
    static func isBlockingItem(
        _ item: AgentPromptItem,
        categories: Set<String> = defaultBlockingCategories
    ) -> Bool {
        // Odmítnutý nález neblokuje ani tady — je to totéž pravidlo jako u odznaku v seznamu:
        // nález, kterému nevěřím, není důvod k ničemu.
        guard case .finding(let finding, let dismissal) = item, dismissal == nil else { return false }
        return isBlocking(finding, categories: categories)
    }

    /// Název souboru, do kterého se zadání nabídne uložit.
    ///
    /// Nese **repo, číslo PR a hlavu**, protože zadání je snímek proti commitu — a dva soubory
    /// z různých commitů téhož PR se od sebe musí poznat i po týdnu ve `~/Downloads`. `owner` se
    /// vynechává: v jedné složce se sejde `PRism-333-…` od dvou vlastníků jednou za život, kdežto
    /// lomítko v názvu souboru je problém pokaždé.
    static func agentPromptFileName(for subject: AgentPromptSubject) -> String {
        let head = subject.shortHead.map { "-\($0)" } ?? ""
        return "\(subject.pullRequest.repo.name)-\(subject.pullRequest.number)-zadani\(head).md"
    }

    /// Sekce bez souboru: **souhrny review, komentáře pod PR, pak nálezy bez místa.**
    ///
    /// Pořadí je z návrhu (sekce 23) a má důvod: souhrn review je to obecné rozhodnutí, kvůli
    /// kterému se změny vyžádaly, komentář pod PR je poznámka k němu a nález bez souboru je
    /// tvrzení o celém PR. Uvnitř každé skupiny chronologicky, položky bez data naspod.
    private static func sortedWholeItems(_ items: [AgentPromptItem]) -> [AgentPromptItem] {
        items.sorted { left, right in
            let leftRank = wholeRank(of: left), rightRank = wholeRank(of: right)
            guard leftRank == rightRank else { return leftRank < rightRank }
            switch (left.date, right.date) {
            case (let leftDate?, let rightDate?) where leftDate != rightDate: return leftDate < rightDate
            case (nil, .some): return false
            case (.some, nil): return true
            default: return left.id < right.id
            }
        }
    }

    private static func wholeRank(of item: AgentPromptItem) -> Int {
        switch item {
        case .review: 0
        case .comment: 1
        case .thread: 2
        case .finding: 3
        }
    }

    private static func sortedFileItems(_ items: [AgentPromptItem]) -> [AgentPromptItem] {
        items.sorted { left, right in
            switch (left.line, right.line) {
            case (let leftLine?, let rightLine?) where leftLine != rightLine: return leftLine < rightLine
            case (nil, .some): return true
            case (.some, nil): return false
            default: return left.id < right.id
            }
        }
    }
}
