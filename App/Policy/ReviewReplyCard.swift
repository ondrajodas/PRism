import Foundation

/// Karta **Odpověď na tvoje review** (#523) — kresba nad tím, co spočítalo #522.
///
/// `ReviewReplyReport` odpovídá na „co se stalo s mými komentáři“; tenhle typ je o patro výš
/// a odpovídá na „co s tím teď“. Je to vlastní vrstva, ne rozšíření reportu, a jsou to dva
/// důvody:
///
/// - **Report se čte i mimo kartu.** Notifikace a řádek v `Dění` (#523) mluví o téže věci
///   a nepotřebují popisky tlačítek ani pořadí řádků; kdyby texty ležely v reportu, vozily by
///   se s ním do banneru, kde nemají co dělat.
/// - **Karta si dovolí říct víc než report.** Report nese fakta; karta z nich skládá **návrh**
///   verdiktu a předepsané tělo, tedy tvrzení, které se dá vyslovit jedině v okně, kde je vidět
///   celé.
///
/// **Nic z toho neodesílá.** Tlačítko `Schválit` předepíše `ReviewDraft` a otevře týž sheet jako
/// dnes (tvrdá podmínka č. 1) — `ReviewVerdict` zůstává návrh a `Policy` nemá jak něco poslat.
extension Policy {
    /// Karta k nakreslení. `nil` = nekreslí se vůbec.
    ///
    /// Nekreslí se ze tří důvodů a každý je vlastní věta:
    ///
    /// - **na vlastním PR nikdy.** „Odpověď na tvoje review“ je otázka o cizí práci; a schválení
    ///   vlastního PR GitHub odmítne (422, změřeno u #62), takže by celá spodní půlka karty byla
    ///   nabídka něčeho, co nejde. Tatáž brána jako u `prefillableSuggestion`.
    /// - **bez načtené konverzace** (`report == .unknown`) — „nevím o svých komentářích nic“ není
    ///   „žádné nemám“, a karta, která by v tom stavu ukázala prázdno, by tvrdila to druhé.
    /// - **bez jediného mého vlákna** — není o čem.
    static func replyCard(
        _ report: ReviewReplyReport,
        ownership: PullRequestOwnership,
        reviewedAt: Date?
    ) -> ReviewReplyCard? {
        guard ownership == .theirs else { return nil }
        guard case .current(let tally) = report, !tally.entries.isEmpty else { return nil }
        let proposal = replyProposal(tally)
        let ordered = tally.entries.sorted { rank(of: $0.state) < rank(of: $1.state) }
        let folded = max(0, tally.fixed - replyCardFixedLimit)
        return ReviewReplyCard(
            title: replyCardTitle(reviewedAt: reviewedAt),
            stamp: tally.verdicts.map {
                ReviewReplyCard.Stamp(checkedAt: $0.finishedAt, headSha: $0.againstHeadSha)
            },
            rows: ordered.dropFirst(folded).map(replyRow(_:)),
            foldedFixed: folded,
            proposal: proposal,
            approvalBody: replyApprovalBody(tally, proposal: proposal),
            openRemaining: firstUnanswered(in: tally),
            caveats: replyCaveats(tally)
        )
    }

    /// Kolik opravených řádků se vypíše, než se zbytek **sečte**.
    ///
    /// Strop je jedině na nich, a je to rozhodnutí: opravený bod je hotová věc, kterou stačí
    /// spočítat, kdežto `odpovězeno` nese větu kolegy a `bez odpovědi` je zrovna to, kvůli čemu
    /// se na kartu kouká — složit je do počtu by schovalo tu polovinu, která něco chce. Přebytek
    /// se proto **počítá, neořezává** (tentýž precedens jako `.lchip.more`, #390).
    static let replyCardFixedLimit = 5

    /// Pořadí řádků: opravené, odpovězené, bez odpovědi.
    ///
    /// Z návrhu (Z3) — a je to pořadí podle **toho, co po mně řádek chce**: nahoře hotové věci,
    /// dole to, na co se musí kliknout. Sbalený přebytek si tím sedne nahoru, tedy k tomu, co se
    /// dá spočítat.
    private static func rank(of state: ReviewReplyState) -> Int {
        switch state {
        case .fixed: 0
        case .answered: 1
        case .unanswered: 2
        }
    }

    /// `Odpověď na tvoje review z 29. 8.` — datum je z **mého posledního odeslaného review**.
    ///
    /// Bez data zůstane věta holá: „z —“ vypadá jako chyba a datum, které v datech není, se
    /// nevymýšlí. Nastane to u PR, kde jsem komentáře odeslal, ale review se z konverzace
    /// nenačetlo (useknutá stránka).
    static func replyCardTitle(reviewedAt: Date?) -> String {
        guard let reviewedAt else { return "Odpověď na tvoje review" }
        return "Odpověď na tvoje review z \(reviewedAt.formatted(.dateTime.day().month()))"
    }

    /// Kdy jsem na PR naposledy odeslal review. `nil` = žádné tam nemám, nebo se nenačetlo.
    ///
    /// **Odeslané, ne rozepsané**: `submittedAt == nil` je `pending` review, tedy to, co ještě
    /// neodešlo — datovat jím kartu by znamenalo tvrdit, že kolega odpovídá na něco, co nikdy
    /// neviděl.
    static func lastOwnReviewDate(in conversation: Conversation?) -> Date? {
        guard let conversation else { return nil }
        return conversation.reviews.items
            .filter { conversation.isMine($0) }
            .compactMap(\.submittedAt)
            .max()
    }

    // MARK: - Návrh verdiktu

    /// Návrh verdiktu nad druhým kolem. **Návrh, ne akce** — odesílá jedině `ReviewPublishing`.
    ///
    /// Rozhoduje **jediná podmínka: zbývá něco bez odpovědi?** Aplikace neschvaluje přes
    /// nezodpovězený bod, takže `opraveno` a `odpovězeno` jsou obojí „vyřízeno“ a jejich poměr
    /// na návrh nemá vliv — na tělo review ano (viz `replyApprovalBody`).
    ///
    /// **Useknutá stránka vláken schválení bere taky**, i když nezodpovězený bod není: o části
    /// vláken PR se neví nic, takže `Schválit` by tvrdilo víc, než data unesou. Je to tentýž
    /// směr opatrnosti jako u `suggestedVerdict`, kde zahozený nález bere approve celému PR.
    ///
    /// Pořadí uvnitř je **konkrétní před obecným**: zbývající komentář se dá otevřít a vyřídit,
    /// kdežto s useknutou stránkou se dělat nedá nic. Že se stránka usekla, se přitom na kartě
    /// ukáže tak jako tak (`caveats`) — to není stav, který by se směl schovat za návrh.
    static func replyProposal(_ tally: ReviewReplyTally) -> ReviewReplyProposal {
        if tally.unanswered > 0 { return .comment(.unanswered(tally.unanswered)) }
        if tally.isTruncated || tally.missingThreads > 0 { return .comment(.incompleteThreads) }
        return .approve
    }

    /// Pruh `návrh: Schválit`, resp. `návrh: Komentář · 1 bez odpovědi`.
    static func replyProposalLabel(_ proposal: ReviewReplyProposal) -> String {
        switch proposal {
        case .approve:
            return "návrh: \(ReviewDraft.Verdict.approve.shortLabel)"
        case .comment(let hesitation):
            let why = switch hesitation {
            case .unanswered(let count): "\(count.formatted()) bez odpovědi"
            case .incompleteThreads: "o všech vláknech nevíme"
            }
            return "návrh: \(ReviewDraft.Verdict.comment.shortLabel) · \(why)"
        }
    }

    /// Popisek tlačítka, kterým se schválení předepíše.
    ///
    /// `Schválit i tak` je **jiné tlačítko než `Schválit`**, i když dělá totéž: rozdíl mezi
    /// „aplikace ti to doporučuje“ a „jdeš proti návrhu“ musí být na obrazovce, ne jen v pruhu
    /// nad tlačítky. Tatáž úvaha jako u `Založit a přidat` (#413).
    static func replyApproveLabel(_ proposal: ReviewReplyProposal) -> String {
        proposal == .approve ? "Schválit" : "Schválit i tak"
    }

    /// Předepsané tělo review. `nil` = nic se nepředepisuje a člověk si ho napíše sám.
    ///
    /// **Píše se jedině tam, kde je návrh `Schválit`.** Poděkovat za něco, co zbylo bez odpovědi,
    /// znamená položit člověku do úst větu, která není pravda — a `Schválit i tak` je vědomé
    /// rozhodnutí jít proti návrhu, ne text k odklikání.
    ///
    /// Věta se skládá z **obou** čísel, ne jen z opravených: `všech 5 opraveno` nad čtyřmi
    /// opravami a jednou odpovědí je tvrzení navíc.
    static func replyApprovalBody(
        _ tally: ReviewReplyTally,
        proposal: ReviewReplyProposal? = nil
    ) -> String? {
        guard (proposal ?? replyProposal(tally)) == .approve else { return nil }
        switch (tally.fixed, tally.answered) {
        case (0, 0):
            // Nemá nastat: karta se bez jediného vlákna nekreslí a vlákno je vždycky v jednom
            // ze tří stavů. Kdyby přesto, neřekne se nic — mlčení je vždycky pravda.
            return nil
        case (let fixed, 0) where fixed == 1:
            return "Díky, opraveno."
        case (let fixed, 0):
            return "Díky, všech \(fixed.formatted()) opraveno."
        case (0, _):
            return "Díky za odpovědi."
        case (let fixed, _):
            return "Díky — \(Plural.czech(fixed, one: "bod", few: "body", many: "bodů"))"
                + " opraveno, na zbytek jsi odpověděl."
        }
    }

    /// Co se doopravdy zapíše do těla draftu. **Rozepsaná věta má přednost před předepsanou.**
    ///
    /// Je to jediná pojistka proti tomu, aby kliknutí na `Schválit` smazalo text, který jsem si
    /// do review napsal — a rozhoduje se to tady, ne ve storu, aby se to dalo vyčerpat výčtem.
    /// Prázdné, jen bílé místo se za rozepsanou větu nepovažuje.
    static func prescribedBody(existing: String, prescribed: String?) -> String {
        guard existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return existing
        }
        return prescribed ?? existing
    }

    // MARK: - Řádky

    /// Jeden řádek karty — značka, místo, moje věta a co se s ní stalo.
    private static func replyRow(_ entry: ReviewReplyEntry) -> ReviewReplyCard.Row {
        ReviewReplyCard.Row(
            threadID: entry.comment.threadID,
            mark: mark(of: entry.state),
            place: replyPlace(of: entry.comment),
            text: shortenedForBanner(entry.comment.body.singleLine),
            note: replyNote(of: entry)
        )
    }

    /// `ř. 81`, u zastaralého vlákna bez kotvy jméno souboru.
    ///
    /// Číslo řádku je to, čím se komentář v druhém kole pozná — a když ho vlákno nemá, je jméno
    /// souboru to jediné, co zbývá. Prázdné místo by z řádku udělalo větu bez podmětu.
    static func replyPlace(of comment: SentComment) -> String {
        guard let line = comment.line else {
            return comment.path.split(separator: "/").last.map(String.init) ?? comment.path
        }
        // Číslo řádku je **adresa, ne množství**, takže se nesází přes `formatted()`:
        // oddělovač tisíců by z `ř. 1234` udělal `ř. 1 234`, tedy dvě čísla na pohled.
        return "ř. \(line)"
    }

    /// Co se s komentářem stalo, jednou větou vpravo.
    ///
    /// **Tři podoby `bez odpovědi`, ne jedna** — `nejde říct` je poctivá odpověď, `beze změny`
    /// je verdikt a `nevyjádřila se` není ani jedno (#522). Slít je znamená tvrdit o komentáři
    /// něco, co běh neřekl; a ani jedna z nich neznamená „ignoroval mě“.
    static func replyNote(of entry: ReviewReplyEntry) -> String {
        switch entry.state {
        case .fixed(let headSha):
            return "opraveno v \(headSha.prefix(7))"
        case .answered:
            guard let reply = entry.reply else { return "odpovězeno ve vlákně" }
            let said = reply.body.singleLine.trimmingCharacters(in: .whitespaces)
            // Prázdné tělo (odpověď jen s obrázkem) nechá **samotného autora**: visící dvojtečka
            // vypadá jako uříznutý text. Tatáž úvaha jako u `commentLine` v banneru.
            guard !said.isEmpty else { return "odpověděl \(reply.author)" }
            return "odpověděl \(reply.author): „\(shortenedForBanner(said))“"
        case .unanswered(let doubt):
            switch doubt {
            case .unchanged: return "bez odpovědi · řádek beze změny"
            case .unclear: return "bez odpovědi · z kódu to nejde říct"
            case .unknown: return "bez odpovědi · kontrola se k tomu nevyjádřila"
            }
        }
    }

    private static func mark(of state: ReviewReplyState) -> ReviewReplyCard.Mark {
        switch state {
        case .fixed: .fixed
        case .answered: .answered
        case .unanswered: .unanswered
        }
    }

    /// První vlákno bez odpovědi — to, které otevře `Otevřít zbývající`. `nil` = žádné není.
    ///
    /// **První v pořadí konverzace**, ne nejzávažnější: závažnost tady neznáme (komentář není
    /// nález a nemá kategorii), takže by se muselo hádat. Pořadí vláken je to, v jakém je vrací
    /// GitHub, tedy totéž, v jakém je vidět na kartě — klik tak míří na řádek, na který se člověk
    /// zrovna dívá.
    private static func firstUnanswered(in tally: ReviewReplyTally) -> ReviewReplyCard.Remaining? {
        guard let entry = tally.entries.first(where: {
            if case .unanswered = $0.state { return true }
            return false
        }) else { return nil }
        return ReviewReplyCard.Remaining(
            threadID: entry.comment.threadID,
            label: "Otevřít zbývající (\(replyPlace(of: entry.comment)))"
        )
    }

    // MARK: - Co karta neví

    /// Čeho se karta **nesmí** zamlčet. Prázdné = ví se všechno.
    static func replyCaveats(_ tally: ReviewReplyTally) -> [ReviewReplyCaveat] {
        var caveats: [ReviewReplyCaveat] = []
        if tally.isTruncated || tally.missingThreads > 0 {
            caveats.append(.incompleteThreads(missing: tally.missingThreads))
        }
        guard let verdicts = tally.verdicts else { return caveats + [.noCheck] }
        if verdicts.outcome != .finished { caveats.append(.checkDidNotFinish) }
        return caveats
    }

    /// Věta k výhradě — jedno místo, ať se karta a testy nerozejdou.
    static func replyCaveatSentence(_ caveat: ReviewReplyCaveat) -> String {
        switch caveat {
        case .incompleteThreads(let missing) where missing > 0:
            let rest = Plural.czech(missing, one: "dalším", few: "dalších", many: "dalších")
            return "Vlákna se do odpovědi nevešla celá — o \(rest) se tady nemluví."
        case .incompleteThreads:
            return "Vlákna se do odpovědi nevešla celá — o zbytku se tady nemluví."
        case .noCheck:
            return "Kontrola nálezů proti téhle hlavě neběžela, takže `opraveno` odsud vyjít"
                + " nemůže. Pusť ji z tabu Nálezy."
        case .checkDidNotFinish:
            return "Kontrola nedoběhla, takže za vlákna, ke kterým se nevyjádřila, nemluví."
        }
    }
}

/// Co se nakreslí na kartě druhého kola (#523).
struct ReviewReplyCard: Equatable, Sendable {
    let title: String
    /// Odkud je osa `opraveno`. `nil` = kontrola neběžela — pak to říká výhrada, ne prázdno.
    let stamp: Stamp?
    /// Opravené, odpovězené, bez odpovědi — v tom pořadí (`Policy.rank(of:)`).
    let rows: [Row]
    /// Kolik opravených bodů se do karty nevešlo a **jen se sečetlo**. `0` = vešly se všechny.
    let foldedFixed: Int
    let proposal: Policy.ReviewReplyProposal
    /// Tělo, které se předepíše do draftu. `nil` = nepředepisuje se nic.
    let approvalBody: String?
    /// Vlákno, na které vede `Otevřít zbývající`. `nil` = nezbývá nic.
    let openRemaining: Remaining?
    /// Čeho se karta nesmí zamlčet. Prázdné = ví se všechno.
    let caveats: [Policy.ReviewReplyCaveat]

    var proposalLabel: String { Policy.replyProposalLabel(proposal) }
    var approveLabel: String { Policy.replyApproveLabel(proposal) }

    /// Proti čemu a kdy se osa modelu pořídila.
    struct Stamp: Equatable, Sendable {
        let checkedAt: Date
        let headSha: String
        /// Sedm znaků, jak se sha píše všude v okně.
        var shortSha: String { String(headSha.prefix(7)) }
    }

    struct Row: Equatable, Sendable, Identifiable {
        /// Identita vlákna z GitHubu — stálá napříč koly, na rozdíl od pořadí i textu.
        let threadID: String
        var id: String { threadID }
        let mark: Mark
        /// `ř. 81`, u vlákna bez kotvy jméno souboru.
        let place: String
        /// Moje věta, zkrácená tímtéž řezem jako v banneru.
        let text: String
        /// Co se s ní stalo.
        let note: String
    }

    /// Značka na začátku řádku. **Tři, ne dvě** — tatáž trojice jako v `ReviewReplyState`.
    enum Mark: Hashable, Sendable {
        case fixed
        case answered
        case unanswered
    }

    /// Kam vede `Otevřít zbývající`.
    struct Remaining: Equatable, Sendable {
        let threadID: String
        let label: String
    }
}

extension Policy {
    /// Co karta navrhuje udělat. **Návrh, ne akce.**
    ///
    /// Vlastní typ vedle `ReviewVerdict`, a je to rozhodnutí: `ReviewVerdict` je návrh **z nálezů**
    /// a `comment` v něm schválně není („je to vědomé nerozhoduju, tedy pravý opak návrhu
    /// odvozeného z nálezů“). Tady je `Komentář` naopak plnohodnotná odpověď — znamená
    /// „neschvaluju, protože něco zbývá“. Přidat ho do `ReviewVerdict` by tu větu rozbilo
    /// a `suggestedVerdict` by najednou uměl vrátit hodnotu, kterou dodnes vrátit nesmí.
    enum ReviewReplyProposal: Hashable, Sendable {
        case approve
        case comment(ReviewReplyHesitation)
    }

    /// Proč se neschvaluje.
    enum ReviewReplyHesitation: Hashable, Sendable {
        /// Tolik mých vláken zůstalo bez odpovědi.
        case unanswered(Int)
        /// Stránka vláken se usekla — o části PR se neví nic.
        case incompleteThreads
    }

    /// Co karta **neví** a musí to přiznat.
    enum ReviewReplyCaveat: Hashable, Sendable {
        /// Kolik vláken PR se do odpovědi nevešlo. `0` znamená „něco chybí, kolik nevíme“
        /// (`hasNextPage` bez rozdílu v počtech).
        case incompleteThreads(missing: Int)
        /// Kontrola proti téhle hlavě neběžela — osa `opraveno` neexistuje.
        case noCheck
        /// Kontrola spadla, vytimeoutovala nebo ji někdo zabil.
        case checkDidNotFinish
    }
}
