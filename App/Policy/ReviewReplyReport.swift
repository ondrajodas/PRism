import Foundation

/// Co se stalo s **mými odeslanými komentáři** v druhém kole (#522).
///
/// **Vlastní typ vedle `RecheckReport`, ne jeho rozšíření**, a jsou to tři důvody, ne úspora:
///
/// - **Jiná platnost.** `RecheckReport` celý zhasne, jakmile se pohne hlava (tvrdá podmínka č.
///   5) — všechno v něm je tvrzení modelu o kódu. Tady je jedna osa **fakt z konverzace**,
///   která se pohybem hlavy nezneplatní; jedno společné `outdated` by ji schovalo taky.
/// - **Jiný klíč.** Nálezy se klíčují `Policy.key(of:)` nad větou revieweera, komentáře identitou
///   vlákna z GitHubu. Dvě klíčování v jedné mapě je přesně to tiché rozpárování, kvůli kterému
///   `FindingKey` existuje.
/// - **Jiný slovník stavů.** `opraveno / odpovězeno / bez odpovědi` není `vyřešeno / pořád platí
///   / nejasné`; přidat do jednoho enumu `odpovězeno` by znamenalo, že u nálezu vznikne stav,
///   který u nálezu nemůže nastat.
///
/// **Neukládá se.** Skládá se při čtení ze dvou zdrojů: z `StoredRecheck` (ten leží na záznamu
/// klíčovaném `(PR, headSha)` a nese `againstHeadSha`, takže tvrdá podmínka č. 5 platí beze
/// změny — nic nového se k `headSha` ani k PR neklíčuje) a z **živé konverzace**, která se
/// nepersistuje vůbec (#63). Třetí uložený stav by musel odpovědi kolegy zmrazit do chvíle
/// posledního běhu a od té chvíle lhát.
extension Policy {
    /// Moje komentáře a co se s nimi stalo.
    ///
    /// - Parameter head: hlava PR, jak ji známe **teď**. `nil` nebo posunutá hlava znamená, že se
    ///   osa modelu nečte vůbec — `opraveno` z ní pak nevyjde u nikoho, protože kontrola mluvila
    ///   o kódu, který v PR už není.
    /// - Parameter conversation: `nil` (nenačetla se) dá `unknown`, ne prázdno: „nevím o svých
    ///   komentářích nic“ a „žádné tam nemám“ jsou dvě různé věty.
    static func replies(
        of record: ReviewRecord?,
        head: String?,
        in conversation: Conversation?
    ) -> ReviewReplyReport {
        guard let conversation else { return .unknown }

        let comments = sentComments(in: conversation)
        // **Jedna množina, ne dvě** (#523): „je vlákno zodpovězené“ a „kdo v něm odpověděl“ je
        // tatáž otázka, takže se odpovídá z jednoho průchodu. Dva by se uměly rozejít a v okně by
        // z toho byl řádek `bez odpovědi` s větou kolegy pod sebou.
        let replies = latestReplies(in: conversation)
        let recheck = currentRecheck(of: record, head: head)

        var entries: [ReviewReplyEntry] = []
        var fixed = 0
        var answers = 0
        var unanswered = 0

        for comment in comments {
            let reply = replies[comment.threadID]
            let isAnswered = reply != nil
            let status = recheck?.replyStatuses[comment.threadID]
            let state = replyState(
                answered: isAnswered,
                verdict: status?.verdict,
                against: recheck?.againstHeadSha
            )
            switch state {
            case .fixed: fixed += 1
            case .answered: answers += 1
            case .unanswered: unanswered += 1
            }
            entries.append(
                ReviewReplyEntry(
                    comment: comment,
                    state: state,
                    // Věta modelu se veze **jen tam, kde model rozhodl**. U `odpovězeno` je stav
                    // z dat, takže vysvětlení od modelu pod ním by vypadalo jako jeho zdroj.
                    note: isAnswered ? nil : status?.note,
                    // A naopak: odpověď kolegy se veze jen tam, kde odpověď **je** (#523). Je to
                    // ta věta, kvůli které se do vlákna jde zpátky, takže by ji karta musela
                    // dohledávat v konverzaci znovu — a to je druhé místo, kde se dá splést.
                    reply: reply
                )
            )
        }

        return .current(
            ReviewReplyTally(
                entries: entries,
                fixed: fixed,
                answered: answers,
                unanswered: unanswered,
                // Useknutá stránka vláken musí být **vidět**: bez toho by `2 opravené ze 3`
                // platilo o třech vláknech, která dorazila, a mlčelo o těch, která ne. Tatáž
                // úmluva jako u `droppedFindings` a `ConversationPage.isTruncated`.
                missingThreads: conversation.threads.missing,
                isTruncated: conversation.threads.isTruncated,
                verdicts: recheck.map {
                    ReviewReplyVerdicts(
                        againstHeadSha: $0.againstHeadSha,
                        outcome: $0.outcome,
                        finishedAt: $0.finishedAt
                    )
                }
            )
        )
    }

    /// Kontrola, která **platí pro dnešní hlavu**. `nil` = neběžela, nebo běžela proti jinému
    /// commitu (tvrdá podmínka č. 5) — obojí znamená, že se její verdikty číst nesmí.
    private static func currentRecheck(of record: ReviewRecord?, head: String?) -> StoredRecheck? {
        guard let recheck = record?.recheck, let head, recheck.againstHeadSha == head else {
            return nil
        }
        return recheck
    }

    /// Stav jednoho komentáře — **jediné místo, kde se ty dvě osy skládají dohromady**.
    ///
    /// Pořadí je `data → model`, a je to rozhodnutí: **fakt přebíjí tvrzení**. Kdyby `opraveno`
    /// přebilo `odpovězeno`, schovala by aplikace odpověď kolegy (kterou si mám přečíst) kvůli
    /// tomu, že se modelu zdálo, že se kód spravil. Opačně se nic neztrácí — ve vlákně s odpovědí
    /// se o opravě stejně dočtu.
    ///
    /// - Parameter verdict: co o komentáři řekla kontrola. `nil` = neptala se, nebo se nevyjádřila.
    /// - Parameter against: hlava, proti které kontrola běžela. `nil` = osa modelu neplatí.
    static func replyState(
        answered: Bool,
        verdict: RecheckStatus.Verdict?,
        against headSha: String?
    ) -> ReviewReplyState {
        if answered { return .answered }
        guard let verdict, let headSha else { return .unanswered(.unknown) }
        switch verdict {
        case .resolved: return .fixed(in: headSha)
        case .stillApplies: return .unanswered(.unchanged)
        case .unclear: return .unanswered(.unclear)
        }
    }

    /// Spáruje odpovědi session s komentáři, na které se ptala.
    ///
    /// **Přes index, ne přes text** (#150) — a index je společný s nálezy: odpověď má jeden tvar,
    /// takže obojí leží v jednom poli a komentáře v něm začínají na `offset`
    /// (`RecheckMaterial.commentIDOffset`). Klíčem výsledku je **identita vlákna**: text komentáře
    /// se mezi koly mění, identita ne.
    ///
    /// `id` mimo rozsah se zahazuje — v jednom poli s nálezy to znamená i **záporný** posun, tedy
    /// odpověď, která patří nálezu. Přiřadit ji komentáři by byl verdikt u cizí věty.
    static func replyStatuses(
        _ answers: [Int: RecheckStatus],
        of comments: [SentComment],
        startingAt offset: Int
    ) -> [String: RecheckStatus] {
        var statuses: [String: RecheckStatus] = [:]
        for (index, status) in answers {
            let position = index - offset
            guard comments.indices.contains(position) else { continue }
            statuses[comments[position].threadID] = status
        }
        return statuses
    }

    /// Druhé kolo nad mými komentáři (#522).
    enum ReviewReplyReport: Equatable, Sendable {
        /// Konverzace se nenačetla — o svých komentářích nevíme **nic**. Není to „žádné nemám“:
        /// prázdný seznam je platná odpověď a tahle není.
        case unknown
        /// Moje komentáře a jejich stavy. Prázdné `entries` znamená, že jsem na PR žádné
        /// odeslané vlákno nezaložil.
        case current(ReviewReplyTally)

        /// Stavy po identitě vlákna — to, z čeho kreslí #523.
        var states: [String: ReviewReplyState] {
            guard case .current(let tally) = self else { return [:] }
            return Dictionary(
                tally.entries.map { ($0.comment.threadID, $0.state) },
                // Dvě vlákna s touž identitou GitHub nevrací; kdyby přece, platí to první —
                // hádat mezi nimi je horší než vzít pořadí, ve kterém odpověď přišla.
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    /// Kolik mých komentářů skončilo jak.
    struct ReviewReplyTally: Equatable, Sendable {
        /// V pořadí konverzace — tedy tak, jak vlákna vrací GitHub.
        let entries: [ReviewReplyEntry]
        let fixed: Int
        let answered: Int
        let unanswered: Int
        /// Kolik vláken se do stránky **nevešlo**. Je to počet přes **všechna** vlákna PR, ne
        /// jen moje: kolik z chybějících je mých, se z odpovědi zjistit nedá, a dopočítat to
        /// odhadem by bylo přesně to tvrzení navíc, kterému se celé #522 vyhýbá.
        let missingThreads: Int
        /// Něco se nevešlo — **i když `missingThreads` vyjde nula**. `hasNextPage` je jediný
        /// signál, který se v nebezpečném směru („máš všechno“) splést nemůže.
        let isTruncated: Bool
        /// Odkud je osa modelu. `nil` = kontrola neběžela, nebo běžela proti jiné hlavě, takže
        /// `opraveno` nemůže vyjít u nikoho. **Musí být vidět**: bez toho se „nikdo nic nespravil“
        /// nepozná od „nikdo se neptal“.
        let verdicts: ReviewReplyVerdicts?
    }

    /// Kdy a proti čemu se osa modelu pořídila.
    struct ReviewReplyVerdicts: Equatable, Sendable {
        /// Hlava, proti které kontrola běžela — to, co se vypisuje v `opraveno v <sha>`.
        let againstHeadSha: String
        /// Jak běh skončil. `timedOut`, `failed` a `interrupted` se nesmí slít s doběhlým:
        /// kontrola, která spadla po dvou odpovědích, za zbytek nemluví.
        let outcome: ReviewRunOutcome
        let finishedAt: Date
    }

    /// Jeden komentář a co se s ním stalo.
    struct ReviewReplyEntry: Equatable, Sendable {
        let comment: SentComment
        let state: ReviewReplyState
        /// Věta, kterou to kontrola odůvodnila. `nil` u stavu z dat i tam, kde model mlčel.
        let note: String?
        /// **Nejnovější cizí odpověď** ve vlákně (#523). `nil` právě tehdy, když stav není
        /// `odpovězeno` — kdo odpověděl a co napsal, je to jediné, čím se ten stav dá v okně
        /// doložit.
        let reply: ThreadComment?

        init(
            comment: SentComment,
            state: ReviewReplyState,
            note: String? = nil,
            reply: ThreadComment? = nil
        ) {
            self.comment = comment
            self.state = state
            self.note = note
            self.reply = reply
        }
    }

    /// Stav jednoho odeslaného komentáře v druhém kole.
    enum ReviewReplyState: Equatable, Sendable {
        /// Kontrola řekla, že to nové commity spravily. **Nese hlavu, proti které to řekla** —
        /// bez ní by to bylo tvrzení bez data platnosti, a tvrdá podmínka č. 5 stojí na opaku.
        case fixed(in: String)
        /// Někdo mi do vlákna odpověděl. **Z dat, ne z modelu** (#72).
        case answered
        /// Ani odpověď, ani oprava — a **proč**.
        case unanswered(ReviewReplyDoubt)
    }

    /// Proč komentář skončil bez odpovědi. **Tři hodnoty, ne jedna**: `nejde říct` je poctivá
    /// odpověď, `beze změny` je verdikt a `nevyjádřila se` není ani jedno. Slít je dohromady by
    /// znamenalo tvrdit o komentáři něco, co běh neřekl — tatáž úvaha jako u `RecheckStatus`.
    enum ReviewReplyDoubt: Equatable, Sendable {
        /// Kontrola řekla, že se na tom místě nic nezměnilo.
        case unchanged
        /// Kontrola z kódu rozhodnout nedokázala.
        case unclear
        /// Kontrola se k tomu komentáři nevyjádřila — neběžela, běžela proti jiné hlavě, nebo
        /// odpověď na tenhle index nedorazila.
        case unknown
    }
}
