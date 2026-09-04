import Foundation

extension Policy {
    /// Kteří reviewery se na tomhle diffu pouštějí — a kteří ne a proč (#518).
    ///
    /// **Čistá funkce nad seznamem souborů a pravidly**, protože je to celé rozhodnutí: reviewer
    /// bez pravidla se pouští, reviewer s pravidlem jedině tehdy, když aspoň jeden soubor diffu
    /// sedí na aspoň jeden jeho vzor. Nic z toho nepotřebuje `git` ani síť, takže se to dá vyzkoušet
    /// výčtem — a runner ani store si o tom nesmí rozhodovat sami.
    ///
    /// **Bez pravidla se pouští vždycky, jako do #518.** Je to ta podmínka, na které stojí, že
    /// přidání routingu nezmění chování repa, které si ho nenastavilo — a platí i pro pravidlo,
    /// ve kterém nezůstal ani jeden použitelný vzor (viz `ReviewerRouting`).
    ///
    /// **Prázdný seznam souborů nepřeskočí nikoho.** Diff bez souborů znamená, že se buď nic
    /// nezměnilo, nebo se cesty nepodařilo zjistit — a v obou případech je bezpečná strana
    /// „pusť to“: přeskočit revieweera kvůli tomu, že jsme se na změněné cesty nedostali, je
    /// tichá ztráta review, kdežto zbytečný běh je jen zbytečný běh. Stejnou stranu drží
    /// `AppStore`, který se na cesty ptá jedině tehdy, když má nějaké pravidlo.
    ///
    /// - Parameters:
    ///   - files: cesty souborů diffu, jak je vydal `git` (`RepoCheckout.changedFiles(in:since:)`).
    ///   - rules: pravidla **v pořadí nastavené sady**, po jednom na revieweera. Skládá je
    ///     `routingRules(of:paths:)`, tedy ne volající.
    static func reviewersToRun(files: [String], rules: [ReviewerRouting]) -> ReviewerRoutingPlan {
        var plan = ReviewerRoutingPlan()
        for rule in rules {
            guard !rule.paths.isEmpty, !files.isEmpty else {
                plan.skills.append(rule.skill)
                continue
            }
            let touched = files.contains { file in
                rule.paths.contains { pathMatches(file, pattern: $0) }
            }
            if touched {
                plan.skills.append(rule.skill)
            } else {
                plan.skipped[rule.skill] = rule.paths
            }
        }
        return plan
    }

    /// Pravidla pro nastavenou sadu — jedno na skill, v jejím pořadí (#518).
    ///
    /// **Čistí vzory na jednom místě**, ze stejného důvodu jako `Configuration.nonBlank`: řádek
    /// v tabulce nastavení vzniká prázdný a prázdný vzor by sedět na nic nemohl. Skill, po kterém
    /// v mapě nic nezbude, dostane pravidlo bez vzorů — tedy „pouštěj vždycky“.
    ///
    /// Vzory se **nepřeskládávají ani nesjednocují**: v pořadí, v jakém stojí v konfiguraci, se
    /// vypisují i v důvodu přeskočení, takže je člověk najde v tabulce tam, kde je napsal.
    static func routingRules(of skills: [String], paths: [String: [String]]) -> [ReviewerRouting] {
        skills.map { skill in
            let patterns = (paths[skill] ?? []).compactMap { pattern -> String? in
                let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return ReviewerRouting(skill: skill, paths: patterns)
        }
    }

    /// Reviewery, které routing na téhle hlavě přeskočil **a přeskočil by je i dnes** (#518).
    ///
    /// Čte to `AppStore.hasCurrentReview`, tedy brána, která automatu brání pustit podruhé review
    /// nad hlavou, která je hotová. Bez ní by na repu s routingem stačil komentář pod PR (mění
    /// `updatedAt`) a automat by si zaplatil celé review znovu, protože přeskočený reviewer žádný
    /// doběhlý běh nemá a nikdy mít nebude.
    ///
    /// **Porovnávají se vzory, ne jen jména.** Přeskočení je odpověď na dnešní pravidlo; jak se
    /// pravidlo změní, přestane platit a review se pustí znovu — což je přesně to, co člověk čeká
    /// od úpravy nastavení. Pravidlo, které se mezitím **zrušilo**, tedy taky neplatí: reviewer
    /// bez pravidla se pouští vždycky.
    ///
    /// - Parameters:
    ///   - pass: co routing přeskočil, i s hlavou, nad kterou to rozhodoval. `nil` = nic se
    ///     nepřeskočilo (a taky se nic nepamatuje — záznam žije jen v paměti).
    ///   - head: hlava, na které PR stojí **teď**. Nesouhlas s `pass.headSha` znamená, že se od
    ///     tohohle rozhodnutí pushlo, takže o dnešní hlavě nevypovídá.
    ///   - rules: dnešní pravidla, ze stejného místa, ze kterého se pouští review.
    static func standingSkips(
        _ pass: ReviewerRoutingPass?,
        head: String,
        rules: [ReviewerRouting]
    ) -> Set<String> {
        guard let pass, pass.headSha == head else { return [] }
        let today = Dictionary(rules.map { ($0.skill, $0.paths) }, uniquingKeysWith: { first, _ in first })
        return Set(pass.skipped.compactMap { skill, patterns in
            guard let current = today[skill], !current.isEmpty, current == patterns else { return nil }
            return skill
        })
    }
}
