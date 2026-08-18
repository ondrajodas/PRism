import Foundation

/// Sazba zadání pro agenta (#333) — markdown, který se dá předat beze změny.
///
/// **Seskupené po souborech, ne po zdrojích.** Agent otevírá soubor, ne revieweera, takže tři
/// poznámky k jednomu souboru patří k sobě i tehdy, když jednu psal robot a dvě člověk. Původ se
/// přitom nese **v textu** u každé položky: podle něj agent pozná, kde se dá odpovědět člověku
/// a kde odpovídat není komu.
///
/// Text je **český**, jako zbytek okna — je to zadání pro agenta, který mluví česky.
extension Policy {
    /// Celý text zadání.
    ///
    /// `diff` slouží jedině k dohledání hunku u nálezu; vlákno svůj `diffHunk` nese samo, takže
    /// `withHunks` musí být vlastní příznak — bez něj by se u nenačteného diffu tiše vypnuly
    /// i hunky u vláken, které se mají kde vzít.
    static func agentPromptText(
        for subject: AgentPromptSubject,
        sections: [AgentPromptSection],
        diff: Diff?,
        withHunks: Bool,
        blocking: Set<String> = defaultBlockingCategories,
        isConversationLoaded: Bool
    ) -> String {
        var blocks = [agentPromptPreamble(
            for: subject,
            count: sections.reduce(0) { $0 + $1.items.count },
            isConversationLoaded: isConversationLoaded
        )]
        for section in sections {
            blocks.append("## \(agentPromptSectionTitle(of: section))")
            for item in section.items {
                blocks.append("### \(agentPromptHeading(of: item, inFileSection: section.file != nil, blocking: blocking))")
                blocks.append(contentsOf: agentPromptBody(of: item))
                if withHunks, let hunk = agentPromptHunk(of: item, in: diff) {
                    blocks.append("```diff\n\(hunk)\n```")
                }
            }
        }
        blocks.append("---")
        blocks.append(agentPromptFooter)
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Úvodní odstavec: kde pracuješ, proti čemu to platí a co které slovo znamená.
    ///
    /// **Hlava PR je tady schválně** (tvrdá podmínka č. 5): nálezy jsou jí klíčované a zadání se
    /// předává dál, takže musí jít poznat, proti čemu vzniklo. Když ji aplikace nezná, řekne se
    /// to — mlčení by vypadalo, že platí pro dnešní kód.
    private static func agentPromptPreamble(
        for subject: AgentPromptSubject,
        count: Int,
        isConversationLoaded: Bool
    ) -> String {
        var lines = ["Pracuješ na PR \(subject.pullRequest)\(agentPromptWhere(of: subject))."]
        lines.append(count == 0
            ? "Aplikace nemá co předat — nálezy ani nevyřízené komentáře na tomhle PR nejsou."
            : "Zbývá vyřešit \(Plural.czech(count, one: "věc", few: "věci", many: "věcí")) z review. U každé je napsané, odkud přišla: „nález“ je z automatického revieweru, „vlákno“ napsal člověk u řádku diffu, „komentář v diskuzi“ a „souhrn review“ jsou z diskuze pod pull requestem. Člověku se dá odpovědět, revieweerovi ne.")
        // Nenačtená konverzace se **říká i v textu**, ne jen v okně: zadání jde dál a bez téhle
        // věty by vypadalo, že cizí komentáře žádné nejsou. Vypnuté volby se tady naopak neopisují
        // — ty jsou moje rozhodnutí, kdežto tohle je mezera v tom, co aplikace ví.
        if !isConversationLoaded {
            lines.append("Konverzace k PR se nenačetla, takže vlákna u řádků, komentáře pod PR ani souhrny review v tomhle zadání nejsou.")
        }
        return lines.joined(separator: "\n")
    }

    /// `ve větvi issue-320-timeout (hlava 9c1de02)`. Větev se vynechá, když ji neznáme; hlava
    /// **nikdy** — místo ní se řekne, že ji aplikace nezná.
    private static func agentPromptWhere(of subject: AgentPromptSubject) -> String {
        let head = subject.shortHead.map { "hlava \($0)" } ?? "hlavu PR aplikace nezná"
        guard !subject.branch.isEmpty else { return " (\(head))" }
        return " ve větvi \(subject.branch) (\(head))"
    }

    private static func agentPromptSectionTitle(of section: AgentPromptSection) -> String {
        section.file ?? "K celému PR (bez souboru)"
    }

    /// Nadpis položky — místo, druh a to, co s ním nesouvisí jinam nedát.
    ///
    /// V sekci bez souboru se místo **nepíše**: „bez řádku“ by u komentáře pod PR bylo tvrzení
    /// o něčem, co komentář nemá mít.
    static func agentPromptHeading(
        of item: AgentPromptItem,
        inFileSection: Bool,
        blocking: Set<String> = defaultBlockingCategories
    ) -> String {
        let origin = agentPromptOrigin(of: item, blocking: blocking)
        guard inFileSection else { return origin }
        return "\(agentPromptPlace(of: item)) — \(origin)"
    }

    /// `řádek 41`, `řádek 88 (zastaralé — číslo platí pro starší commit)`, nebo `bez řádku`.
    private static func agentPromptPlace(of item: AgentPromptItem) -> String {
        guard let line = item.line else { return "bez řádku" }
        // Zastaralé vlákno se umisťuje podle `originalLine` a **musí to být napsané**: tvrdit
        // dnešní řádek u kotvy, která platila pro starý head, je horší než nic.
        if case .thread(let thread) = item, thread.line == nil || thread.isOutdated {
            return "řádek \(line) (zastaralé — číslo platí pro starší commit)"
        }
        return "řádek \(line)"
    }

    private static func agentPromptOrigin(
        of item: AgentPromptItem,
        blocking: Set<String>
    ) -> String {
        switch item {
        case .finding(let finding, let dismissal):
            var marks = [finding.reviewer]
            if let category = finding.category, !category.isEmpty { marks.append(category) }
            var origin = "nález (\(marks.joined(separator: ", ")))"
            if isBlockingItem(item, categories: blocking) { origin += " — BLOKUJE" }
            // Odmítnutý nález se do zadání dostane jedině na výslovné přání, takže se **označí**:
            // agent má vědět, že tomuhle nálezu člověk nevěří.
            if let dismissal { origin += " — ODMÍTNUTÝ NÁLEZ (\(dismissal.label))" }
            return origin
        case .thread(let thread):
            var marks = [thread.comments.items.first?.author ?? "neznámý autor"]
            marks.append(thread.isResolved ? "vyřešené" : "nevyřešené")
            let replies = max(0, thread.comments.items.count - 1)
            if replies > 0 {
                marks.append(Plural.czech(replies, one: "odpověď", few: "odpovědi", many: "odpovědí"))
            }
            return "vlákno (\(marks.joined(separator: ", ")))"
        case .comment(let comment):
            return "komentář v diskuzi — \(comment.author)"
        case .review(let review):
            return "souhrn review — \(review.author), \(review.state?.czechLabel ?? "neznámý stav")"
        }
    }

    /// Text položky tak, jak se do zadání vysází — a **totéž**, co se ukáže v rozkliku (#377).
    ///
    /// Jedna funkce na obojí schválně: rozklik je tu proto, aby se dalo posoudit, co se předává,
    /// takže druhá cesta k témuž textu by dřív nebo později ukázala něco jiného, než co odejde.
    /// Prázdný výsledek znamená „položka nic nenese“ (schválení s prázdným tělem) a rozhoduje
    /// podle něj `Policy.pickDisclosure(of:toggled:)`, jestli se u řádku vůbec kreslí šipka.
    static func agentPromptItemText(of item: AgentPromptItem) -> String {
        agentPromptBody(of: item).joined(separator: "\n\n")
    }

    /// Text položky — a u vlákna i odpovědi v něm.
    ///
    /// Odpovědi se **nezahazují**: „o tomhle už se mluvilo“ mění zadání, protože bez nich agent
    /// napíše totéž znovu. Nesou proto autora, ať je z nich poznat, komu se odpovídá.
    static func agentPromptBody(of item: AgentPromptItem) -> [String] {
        switch item {
        case .finding(let finding, _):
            var blocks = [finding.summary]
            if let scenario = finding.failureScenario, !scenario.isEmpty {
                blocks.append("Kdy to selže: \(scenario)")
            }
            return blocks
        case .thread(let thread):
            let comments = thread.comments.items
            var blocks = [comments.first?.body ?? "(text vlákna nedorazil)"]
            blocks += comments.dropFirst().map { "Odpověď od \($0.author): \($0.body)" }
            if thread.comments.isTruncated {
                blocks.append("(z vlákna dorazila jen část odpovědí — zbytek je na GitHubu)")
            }
            return blocks
        case .comment(let comment):
            return [comment.body]
        // Souhrn bez prózy se do seznamu dostane jen s verdiktem (`isVerdict`), a ten je
        // v nadpisu. Prázdný odstavec pod ním by vypadal jako ztracený text.
        case .review(let review):
            return review.body.isEmpty ? [] : [review.body]
        }
    }

    /// Diff hunk k položce. `nil` = není z čeho ho vzít.
    ///
    /// U vlákna je to `diffHunk` z GitHubu, tedy **snímek z commitu, na kterém vlákno vzniklo** —
    /// u zastaralého vlákna je to jediný kód, o kterém je řeč. U nálezu se hledá hunk v dnešním
    /// diffu podle čísla řádku; bez načteného diffu se nepřiloží nic.
    private static func agentPromptHunk(of item: AgentPromptItem, in diff: Diff?) -> String? {
        switch item {
        case .thread(let thread):
            guard let hunk = thread.diffHunk, !hunk.isEmpty else { return nil }
            return hunk
        case .finding(let finding, _):
            guard let path = finding.file, let line = finding.line,
                  let file = diff?.file(at: path),
                  let hunk = file.hunks.first(where: { hunk in hunk.lines.contains { $0.newNumber == line } })
            else { return nil }
            return unifiedText(of: hunk)
        case .comment, .review:
            return nil
        }
    }

    /// Hunk jako unified diff — hlavička a řádky se znaky změny.
    ///
    /// **Se znaky, na rozdíl od `Policy.code(of:)`**: tam se kopíruje kód do editoru, kdežto tady
    /// jde o to, co se v tom místě změnilo. Poznámky `git`u (`\ No newline at end of file`) se
    /// vynechávají ze stejného důvodu jako u kopie — nejsou obsah souboru.
    static func unifiedText(of hunk: DiffHunk) -> String {
        let lines = hunk.lines.filter { $0.kind != .meta }.map { line in
            switch line.kind {
            case .added: "+\(line.text)"
            case .removed: "-\(line.text)"
            case .context, .meta: " \(line.text)"
            }
        }
        return ([hunk.header] + lines).joined(separator: "\n")
    }

    /// Patička. **Neslibuje pravidla, která zadání nenese** — repo si agent přečte sám.
    private static var agentPromptFooter: String {
        "Pravidla repa si vezmi z repa (`CLAUDE.md`, `CONTRIBUTING.md`) — v tomhle zadání nejsou. Až budeš hotový, do vláken od lidí se dá odpovědět; kdo je napsal, stojí výš u každého z nich."
    }
}
