import Foundation

/// Co dashboard ukazuje (#181).
///
/// Startovní obrazovka odpovídá na tři otázky, které se do #181 v okně nedaly zodpovědět naráz:
/// **kolik toho je**, **co z toho blokuje** a **co jsem si nedodělal**. Všechna čísla už
/// v aplikaci byla, jen roztroušená po stavovém řádku a po řádcích seznamu.
struct Dashboard: Hashable, Sendable {
    let queue: QueueCard
    let blocking: BlockingCard
    /// Moje vlastní PR (#331) — druhá fronta, ne podmnožina té první.
    let mine: MineCard
    let drafts: DraftsCard
    /// Podíl reviewerů na nálezech za posledních pár dní.
    let reviewers: [ReviewerShareOfFindings]

    /// Kolik PR čeká a z kolika repozitářů. Repozitáře patří do popisku, protože „pět PR“
    /// z jednoho repa je jiná práce než pět z pěti.
    struct QueueCard: Hashable, Sendable {
        let pullRequests: Int
        let repositories: Int
    }

    /// Kolik PR blokuje a **čím** — kategorie a repo toho nejzávažnějšího.
    ///
    /// `detail` je `nil`, když nic neblokuje **nebo** když se o důvodu nedá nic říct; karta pak
    /// ukáže jen číslo. Vymyslet kategorii k nálezu, který ji nemá, by znamenalo tvrdit, proč
    /// se PR nemerguje, a mýlit se v tom.
    struct BlockingCard: Hashable, Sendable {
        let pullRequests: Int
        let detail: String?
    }

    /// Kolik mám otevřených vlastních PR a na kolika z nich leží můj tah (#331).
    ///
    /// **Dvě čísla, ne jedno**, a je to celý důvod, proč karta vznikla: velké číslo je „kolik
    /// toho mám venku“, kdežto věta pod ním „kolik z toho čeká na mě“. Šest otevřených PR, ze
    /// kterých pět čeká na CI, není šest věcí k práci.
    ///
    /// `isTracked == false` znamená, že mezi zdroji chybí `author:@me` — pak je nula údaj
    /// o **nastavení**, ne o mojí práci, a věta pod číslem to musí říct. Bez toho příznaku by
    /// nenastavená aplikace vypadala jako uklizený stůl.
    struct MineCard: Hashable, Sendable {
        let pullRequests: Int
        /// Kolik z nich má nezpracovaný nález nebo nevyřešené cizí vlákno. Spodní hranice —
        /// viz `Policy.ownPullRequestsAwaitingMove`.
        let awaitingMove: Int
        let isTracked: Bool
    }

    /// Kolik PR má rozdělané review a jak dlouho leží to nejstarší.
    ///
    /// `oldest` je `nil` u draftů z doby před #181, které razítko nemají — „leží 0 dní“ by
    /// u nich bylo tvrzení, které z dat neplyne. `pullRequest` je i tak vyplněný: pokračovat
    /// se v něm dá, i když se neví, odkdy leží.
    struct DraftsCard: Hashable, Sendable {
        let pullRequests: Int
        let oldest: Date?
        /// Ten nejstarší — cíl akce `Dopsat review`. `nil`, když nic rozdělaného není.
        let pullRequest: PRIdentifier?
    }
}

/// Kolik nálezů má na svědomí jeden reviewer.
struct ReviewerShareOfFindings: Hashable, Sendable, Identifiable {
    let reviewer: String
    let findings: Int

    var id: String { reviewer }
}

extension Policy {
    /// Složí dashboard z toho, co je v paměti store.
    ///
    /// Bere **plný** seznam, ne zúžený filtrem (#117): dashboard je tvrzení o tom, co ve frontě
    /// **je**, ne o tom, co je zrovna vidět — tatáž úvaha jako u souhrnu ve stavovém řádku.
    ///
    /// **Karta `Moje PR` se počítá tady, ne vedle** (#331). Dashboard je jeden snímek, který si
    /// view bere **jednou za překreslení**, takže druhý getter na jednu jeho kartu by znamenal
    /// druhý průchod seznamem a druhou pravdu o jedné obrazovce.
    ///
    /// **Karta `Čeká na mě` počítá pořád celý seznam**, tedy i moje PR — odříznout je patří k #332,
    /// které mění i frontu, automat a notifikace. Do té doby se moje PR na dashboardu objeví
    /// v obou blocích.
    static func dashboard(
        pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord],
        drafts: [PRIdentifier: ReviewDraft],
        categories: Set<String> = defaultBlockingCategories,
        since: Date? = nil,
        mine: Set<String> = [],
        conversation: (PRIdentifier) -> Conversation? = { _ in nil },
        tracksOwnSource: Bool = false
    ) -> Dashboard {
        let blocking = pullRequests.filter { blockingCount(in: records[$0.id], categories: categories) > 0 }
        let own = self.pullRequests(pullRequests, ownedBy: .mine, mine: mine)

        return Dashboard(
            queue: Dashboard.QueueCard(
                pullRequests: pullRequests.count,
                repositories: Set(pullRequests.map(\.repo)).count
            ),
            blocking: Dashboard.BlockingCard(
                pullRequests: blocking.count,
                detail: blockingDetail(of: blocking, records: records, categories: categories)
            ),
            mine: Dashboard.MineCard(
                pullRequests: own.count,
                awaitingMove: ownPullRequestsAwaitingMove(
                    own,
                    records: records,
                    conversation: conversation
                ),
                isTracked: tracksOwnSource
            ),
            drafts: draftsCard(of: pullRequests, drafts: drafts),
            reviewers: reviewerShares(in: records, since: since)
        )
    }

    /// Rozdělaná review: **PR ve frontě s neprázdným draftem**, tedy přesně to, co počítá souhrn
    /// ve stavovém řádku (#155).
    ///
    /// Do #181 se tu počítaly všechny drafty na disku, a karta pak tvrdila „3“ vedle stavového
    /// řádku s jedničkou. Rozdíl dělá dvojí: prázdný draft (vznikne otevřením panelu a smazáním
    /// napsaného znaku) a draft na PR, který už ve frontě není.
    private static func draftsCard(
        of pullRequests: [PullRequestSummary],
        drafts: [PRIdentifier: ReviewDraft]
    ) -> Dashboard.DraftsCard {
        let drafted = pullRequests.filter { drafts[$0.id]?.isEmpty == false }
        // Nejstarší podle razítka. Drafty z doby před #181 razítko nemají, takže se řadí za ty
        // orazítkované a v kartě se u nich o stáří nemluví — pokračovat se v nich ale dá.
        let oldest = drafted.min { left, right in
            switch (drafts[left.id]?.updatedAt, drafts[right.id]?.updatedAt) {
            case let (leftStamp?, rightStamp?): leftStamp < rightStamp
            case (nil, _?): false
            case (_?, nil): true
            case (nil, nil): left.id < right.id
            }
        }
        return Dashboard.DraftsCard(
            pullRequests: drafted.count,
            oldest: oldest.flatMap { drafts[$0.id]?.updatedAt },
            pullRequest: oldest?.id
        )
    }

    /// Kolik platných nálezů záznamu blokuje. `nil` záznam = žádné.
    private static func blockingCount(in record: ReviewRecord?, categories: Set<String>) -> Int {
        record.map { blockingCount(in: $0, categories: categories) } ?? 0
    }

    /// `correctness · keboola/vault` — kategorie a repo prvního blokujícího nálezu v pořadí,
    /// ve kterém je řadí `Policy`. Tedy toho, který je nahoře i v panelu; dashboard a panel
    /// nesmí ukazovat jako „ten nejhorší“ každý jiný.
    private static func blockingDetail(
        of pullRequests: [PullRequestSummary],
        records: [PRIdentifier: ReviewRecord],
        categories: Set<String>
    ) -> String? {
        for pullRequest in pullRequests {
            guard let record = records[pullRequest.id] else { continue }
            let sorted = self.sorted(record.activeFindings, categories: categories, dismissals: record.dismissals)
            guard
                let worst = sorted.first(where: { isBlocking($0, categories: categories) }),
                let category = worst.category
            else { continue }
            return "\(category) · \(pullRequest.repo)"
        }
        return nil
    }

    /// Nálezy podle reviewera, od nejvíce k nejméně.
    ///
    /// Počítají se **platné** nálezy (bez odmítnutých) z běhů, které doběhly po `since`.
    /// Reviewer, který v okně běžel a nic nenašel, v seznamu **zůstává s nulou**: „nenašel nic“
    /// je výsledek, kdežto chybějící řádek by vypadal, že neběžel.
    private static func reviewerShares(
        in records: [PRIdentifier: ReviewRecord],
        since: Date?
    ) -> [ReviewerShareOfFindings] {
        var counts: [String: Int] = [:]
        for record in records.values {
            let active = Set(record.activeFindings.map(key(of:)))
            for run in record.runs where since.map({ run.finishedAt >= $0 }) ?? true {
                // Přes klíč, ne přes rovnost nálezů: `activeFindings` je filtr nad týmiž
                // instancemi, ale identita nálezu se v tomhle repu skládá jedině `Policy.key`.
                counts[run.skillID, default: 0] += run.findings.count { active.contains(key(of: $0)) }
            }
        }
        return counts
            .map { ReviewerShareOfFindings(reviewer: $0.key, findings: $0.value) }
            // Od nejvíc nálezů, při shodě podle jména. Rozepsané, ne přes prohozenou dvojici:
            // slovník pořadí nemá, takže druhé kritérium je to jediné, co drží legendu klidnou
            // mezi překreslením — a musí být z kódu vidět, ne z triku s obrácenými prvky.
            .sorted {
                if $0.findings != $1.findings { return $0.findings > $1.findings }
                return $0.reviewer < $1.reviewer
            }
    }
}
