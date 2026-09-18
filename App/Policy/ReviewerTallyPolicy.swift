import Foundation

/// Součet odmítnutí po reviewerech (#514).
///
/// **Čistá funkce nad tím, co je na disku — nic se nepočítá při běhu.** Je to vědomě opačné
/// rozhodnutí než u útraty (`SpendLedger`), a je to proto, že ta dvě čísla mají jinou povahu:
/// utracené peníze zůstanou utracené, i když záznam zahodím, kdežto odmítnutí **je** ten
/// záznam. Počitadlo vedle něj by se s ním umělo rozejít a nešlo by poznat, které z těch dvou
/// čísel je pravda.
extension Policy {
    /// Okno součtu — **třicet dní**, a je to filtr, ne vlastnost úklidu.
    ///
    /// `ReviewStore.defaultRetention` je taky třicet dní, ale měří se **od chvíle, kdy PR zmizel
    /// ze sledovaného seznamu** (`ReviewRecord.closedAt`) — záznam otevřeného PR tedy leží na
    /// disku libovolně dlouho. Kdyby se blok spolehl na úklid, tvrdil by `30 dní` nad daty
    /// z půl roku. Ořezává se proto tady, a to podle toho, **kdy běh doběhl**.
    static let reviewerTallyWindow: TimeInterval = 30 * 24 * 60 * 60

    /// Přes kolik odmítnutí se věta ozve — **jeden práh, ne tři**.
    ///
    /// Je nad **součtem obou důvodů** (`ReviewerTally.dismissed`), ne nad jedním z nich: reviewer,
    /// u kterého polovina nálezů neobstála, je problém i tehdy, když se to dělí napůl mezi
    /// „mýlí se“ a „sem to nepatří“. Který z těch dvou se pak ve větě pojmenuje, je druhá otázka
    /// (`reviewerSignal(of:)`) a práh s ní nemá co dělat.
    ///
    /// Porovnává se **ostře** — `přes polovinu`, tedy 7 ze 14 mlčí a 8 ze 14 mluví.
    static let reviewerDismissalThreshold = 0.5

    /// Pod kolika nálezy věta mlčí, i když je podíl nad prahem.
    ///
    /// **Podíl sám o sobě neunese větu s imperativem.** `3 ze 4 neplatí → skill` se čte stejně
    /// naléhavě jako `9 ze 14`, přitom je to o jedno kliknutí od `2 ze 4`, tedy od stavu, ve
    /// kterém by věta zmizela. Nad čtyřmi nálezy je navíc pruh nad větou celý příběh — jsou to
    /// čtyři věty, které se prostě přečtou; věta, která posílá opravit skill, začíná dávat smysl
    /// teprve tam, kde se ten pruh číst nevyplatí.
    ///
    /// Pod prahem se **nekreslí prázdno**, ale prostý součet (`31 z 38 převzato`) — řádek, který
    /// zmlkne úplně, vypadá jako chybějící data.
    static let reviewerSignalFloor = 5

    /// Kolik řádků se vejde do bloku na Přehledu. Zbytek je v Nastavení, kam vede odkaz
    /// v hlavičce bloku — tentýž strop jako u ostatních bloků pravého sloupce.
    static let reviewerTallyBoardLimit = 4

    /// Sečte odmítnutí po dvojicích `(repo, reviewer)`.
    ///
    /// **Nález se počítá jednou za pull request, ne jednou za uložený soubor.** Přírůstkové review
    /// (#517) přenese nález z minulé hlavy na dnešní, takže týž nález leží ve dvou záznamech
    /// jednoho PR — bez slití by se dvakrát započítal ten, u kterého reviewer dvakrát trval na
    /// svém, tedy zrovna ten nejspolehlivější. Slívá se podle `Policy.key(of:)`, tedy toutéž
    /// identitou, kterou se páruje odmítnutí.
    ///
    /// **Uzavřený případ je `převzato`, živý `nerozhodnuto`.** Nález, který visí na hlavě, která
    /// už není (`isStale`), nebo na PR, který ze seznamu zmizel (`closedAt`), jsem buď předal,
    /// nebo nechal projít — v obou případech jsem se o něm rozhodl tím, že jsem ho neodmítl.
    /// Nález na živé hlavě může být prostě nepřečtený, a ten se za schválení vydávat nesmí.
    /// Přenesený nález (`Finding.carriedFrom`) je `převzato` ze stejného důvodu: přežil push,
    /// na kterém jsem ho mohl odmítnout.
    ///
    /// - Parameter records: **všechny** záznamy z disku, ne `currentRecords` — odmítnutí leží
    ///   u nálezu, tedy u té hlavy, na které vznikl, a odmítnutý nález se navíc nepřenáší (#517).
    static func reviewerTallies(from records: [ReviewRecord], now: Date) -> [ReviewerTally] {
        let since = now.addingTimeInterval(-reviewerTallyWindow)
        var byGroup: [Group: [Slot: Disposition]] = [:]

        for record in records {
            // Uzavřený případ — viz doc výš. Rozhoduje se **jednou za záznam**, ne za nález.
            let isSettled = record.isStale || record.closedAt != nil
            for run in record.runs where run.finishedAt >= since {
                for finding in run.findings {
                    let key = Policy.key(of: finding)
                    let group = Group(repo: record.pullRequest.repo, reviewer: finding.reviewer)
                    let slot = Slot(pullRequest: record.pullRequest, finding: key)
                    let disposition = disposition(
                        of: finding,
                        dismissal: record.dismissals[key],
                        isSettled: isSettled
                    )
                    // Silnější stav vyhrává: rozhodnutý nález nesmí zeslábnout na „nerozhodnuto“
                    // jen proto, že jeho kopie leží i v záznamu, který o něm nic neví.
                    let previous = byGroup[group]?[slot] ?? .undecided
                    byGroup[group, default: [:]][slot] = max(previous, disposition)
                }
            }
        }

        return byGroup.map { group, slots in
            var tally = ReviewerTally(reviewer: group.reviewer, repo: group.repo)
            for disposition in slots.values {
                switch disposition {
                case .undecided: tally.undecided += 1
                case .taken: tally.taken += 1
                case .irrelevant: tally.irrelevant += 1
                case .invalid: tally.invalid += 1
                }
            }
            return tally
        }
        .sorted(by: isAheadInTally)
    }

    /// Věta pod pruhem. `nil` u řádku bez jediného nálezu — ten se nemá kde vzít, ale kdyby
    /// vznikl, `0 z 0 převzato` je věta, která netvrdí nic.
    static func reviewerSignal(of tally: ReviewerTally) -> ReviewerSignal? {
        guard tally.total > 0 else { return nil }
        guard tally.total >= reviewerSignalFloor,
              Double(tally.dismissed) > Double(tally.total) * reviewerDismissalThreshold
        else {
            return ReviewerSignal(text: "\(tally.taken) z \(tally.total) převzato", aim: .none)
        }
        // **Shoda padá na `Neplatí`**, protože ta věta míří na skill — tedy na to, co se opravit
        // dá. `Nepatří sem` posílá přepsat pravidla repa, a to je při rovnosti slabší tvrzení.
        if tally.invalid >= tally.irrelevant {
            return ReviewerSignal(
                text: "\(tally.invalid) z \(tally.total) neplatí → skill",
                aim: .skill
            )
        }
        return ReviewerSignal(
            text: "\(tally.irrelevant) z \(tally.total) nepatří sem → pravidla repa",
            aim: .repoRules
        )
    }

    /// Podíl do tabulky v Nastavení — `64 % neplatí`, `82 % převzato`.
    ///
    /// **Pojmenuje se to, čeho je nejvíc**, ne to, co je nad prahem: tabulka je plný výpis, takže
    /// u ní nejde o výstrahu, ale o to, jak ten reviewer dopadá. Práh se sem proto netahá.
    ///
    /// **Při shodě vyhrává odmítnutí, ne `převzato`** (`neplatí` > `nepatří sem` > `převzato` >
    /// `nerozhodnuto`). Řádek `5 převzato / 5 nepatří sem` má stejně dobře pravdu z obou stran
    /// a tabulka je o tom, co reviewery zdržuje — takže se vypíše ta polovina, se kterou se dá
    /// něco udělat. Je to tatáž volba jako v zákresu (*5 z 11 nepatří sem*).
    ///
    /// Procento se zaokrouhluje na celé (`45,45 %` → `45 %`): desetina procenta nad čtrnácti
    /// nálezy je přesnost, kterou data nemají.
    static func reviewerShare(of tally: ReviewerTally) -> ReviewerSignal? {
        guard tally.total > 0 else { return nil }
        let (count, word, aim): (Int, String, ReviewerSignal.Aim) =
            if tally.invalid >= tally.irrelevant, tally.invalid >= tally.taken,
               tally.invalid >= tally.undecided, tally.invalid > 0 {
                (tally.invalid, "neplatí", .skill)
            } else if tally.irrelevant >= tally.taken, tally.irrelevant >= tally.undecided,
                      tally.irrelevant > 0 {
                (tally.irrelevant, "nepatří sem", .repoRules)
            } else if tally.taken >= tally.undecided {
                (tally.taken, "převzato", .none)
            } else {
                (tally.undecided, "nerozhodnuto", .none)
            }
        let percent = Int((Double(count) / Double(tally.total) * 100).rounded())
        return ReviewerSignal(text: "\(percent) % \(word)", aim: aim)
    }

    /// Složka skillu, kterou má otevřít `Otevřít skill ↗`. `nil` = aplikace ji nezná, a pak se
    /// **tlačítko nekreslí vůbec** — ne zašedle: zašedlé tlačítko tvrdí „tady se to dělá, jen
    /// teď ne“, kdežto u skillu bez zapsané cesty se to nedá nikdy.
    ///
    /// Cesta se bere z konfigurace (`Configuration.Global.skillFolders`) a **vlnovka se
    /// rozbaluje**: v ručně psaném `config.json` je `~/.claude/skills/code-review` to, co člověk
    /// napíše, kdežto `URL(fileURLWithPath:)` by z toho udělal složku jménem `~` vedle aplikace.
    /// Relativní cesta se odmítá ze stejného důvodu — proti čemu by byla relativní, se z GUI
    /// aplikace bez zděděného `PATH` nedá říct.
    static func skillFolder(of reviewer: String, in folders: [String: String]) -> URL? {
        guard let raw = folders[reviewer]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let expanded = NSString(string: raw).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    /// Pořadí řádků — **nahoře, kde je co opravit**.
    ///
    /// Jedno řazení pro blok i pro tabulku: blok je řez prvních `reviewerTallyBoardLimit` řádků
    /// téhož seznamu, takže dvě řazení by znamenala, že se do bloku dostane něco jiného, než co
    /// v tabulce stojí nahoře.
    ///
    /// Rozhoduje **podíl odmítnutých**, ne jejich počet: reviewer s pěti odmítnutími ze šesti je
    /// horší než ten s deseti ze sta. Při shodě jde napřed ten s víc nálezy (víc dat), pak
    /// abecedně — pořadí musí být úplné, jinak se výpis mezi dvěma překresleními zamíchá.
    private static func isAheadInTally(_ lhs: ReviewerTally, _ rhs: ReviewerTally) -> Bool {
        let left = Double(lhs.dismissed) / Double(lhs.total)
        let right = Double(rhs.dismissed) / Double(rhs.total)
        if left != right { return left > right }
        if lhs.total != rhs.total { return lhs.total > rhs.total }
        if lhs.reviewer != rhs.reviewer { return lhs.reviewer < rhs.reviewer }
        return lhs.repo.description < rhs.repo.description
    }

    private static func disposition(
        of finding: Finding,
        dismissal: FindingDismissal?,
        isSettled: Bool
    ) -> Disposition {
        switch dismissal?.reason {
        case .invalid: .invalid
        case .irrelevant: .irrelevant
        case nil: isSettled || finding.carriedFrom != nil ? .taken : .undecided
        }
    }

    /// Řádek výpisu. Jen jako klíč slučování — ven se nedostane.
    private struct Group: Hashable {
        let repo: RepoID
        let reviewer: String
    }

    /// Jeden nález jednoho PR napříč jeho uloženými hlavami — viz slití v `reviewerTallies`.
    private struct Slot: Hashable {
        let pullRequest: PRIdentifier
        let finding: FindingKey
    }

    /// Co se s nálezem stalo. **`Comparable` schválně**: pořadí případů je „jak moc je o nálezu
    /// rozhodnuto“ a slití dvou kopií téhož nálezu bere tu silnější.
    private enum Disposition: Comparable {
        case undecided
        case taken
        case irrelevant
        case invalid
    }
}
