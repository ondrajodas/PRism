import Foundation

/// Co na **vlastním** PR udělal někdo jiný (#335).
///
/// Je to **druhý druh novosti** vedle „co zbývá předat“ (`HandoffReport`): u cizího PR je novinka
/// to, že po mně někdo chce review, u vlastního to, že se v diskuzi ozval kolega — a právě kvůli
/// tomu se chodí na GitHub. Nese se to proto jako výsledek `Policy.handoff(…)`, ne jako vlastní
/// odpověď vedle ní: kdyby si na „co je nového“ odpovídal řádek seznamu sám, rozešel by se
/// s odznakem v railu i s panelem.
///
/// **Commity v tom nejsou schválně.** Na vlastním PR je push obvykle můj, a odlišit cizí push od
/// mého rebase se z těch dat spolehlivě nedá: `TimelineEvent.at` je u commitu **datum commitu, ne
/// pushnutí** (`pushedDate` GitHub neplní, změřeno u #171) a `actor` u něj chybět může. Banner
/// „někdo pushnul“ by tak chodil o vlastní práci. Pruh „od tvé poslední návštěvy“ v detailu PR
/// commity ukazuje dál — tam je vidět celý kontext, kdežto tady jde o jednu větu v notifikaci.
struct ForeignActivity: Hashable, Sendable {
    /// Cizí komentáře — pod PR i ve vláknech, od nejstaršího. Moje vlastní v tom nejsou: že jsem
    /// něco napsal já, není novinka (tatáž úvaha jako u `Policy.changes(in:since:)`).
    let comments: [ThreadComment]
    /// Cizí odeslaná review — včetně Copilotova.
    let reviews: [SubmittedReview]

    static let none = ForeignActivity(comments: [], reviews: [])

    var isEmpty: Bool { comments.isEmpty && reviews.isEmpty }

    var count: Int { comments.count + reviews.count }

    /// Kdy přišlo to nejnovější — razítko oznámení (`ActivityNoticeLedger`).
    ///
    /// `nil` jedině u prázdné aktivity. Bere se **datum položky**, ne „teď“: kdyby se do razítka
    /// zapsal čas doručení, propadl by komentář, který přišel mezi dotazem a zápisem.
    var latest: Date? {
        (comments.map(\.createdAt) + reviews.compactMap(\.submittedAt)).max()
    }
}

extension Policy {
    /// Cizí aktivita od `date`. `nil` (PR jsem nikdy neviděl a nikdy se o něm nehlásilo) dá
    /// **prázdno**, ne celou historii — tatáž úvaha jako u `changes(in:since:)`.
    ///
    /// **Staví na `changes(in:since:)`**, ne na vlastním průchodu konverzací: „co přišlo po téhle
    /// chvíli“ je jedna otázka a druhá odpověď na ni by se s první rozešla (u komentářů se navíc
    /// odfiltrují ty moje, což je pravidlo, které se nemá psát dvakrát). Zbývá vybrat, co z toho je
    /// **cizí aktivita**: komentáře a review, bez mých vlastních review — na vlastní PR sice
    /// verdikt poslat nejde, ale komentované review ano.
    static func foreignActivity(in conversation: Conversation?, since date: Date?) -> ForeignActivity {
        guard let conversation else { return .none }
        let changes = changes(in: conversation, since: date)
        return ForeignActivity(
            comments: changes.comments,
            reviews: changes.reviews.filter { !conversation.isMine($0) }
        )
    }

    /// Proti čemu se poznává, o čem se **ještě nedalo vědět** (#335).
    ///
    /// Dvě razítka, protože jsou to dvě různé věci: `VisitLedger` drží poslední **návštěvu**,
    /// `ActivityNoticeLedger` poslední **oznámení** — a oznámením PR nenavštívím. Bez toho druhého
    /// by „2 nové komentáře“ chodily každou rozhlídku, dokud PR neotevřu; bez toho prvního by se
    /// hlásilo i to, co jsem v okně už přečetl.
    ///
    /// Bere se **pozdější** z nich: novinka je to, co je novější než obojí. `nil` (ani jedno
    /// razítko) znamená **ticho** — u PR, který jsem nikdy neviděl, by „od minule“ znamenalo „od
    /// začátku věků“ a při prvním spuštění by z toho byla lavina o měsíc starých komentářích.
    static func activityBaseline(lastVisit: Date?, lastNotice: Date?) -> Date? {
        [lastVisit, lastNotice].compactMap { $0 }.max()
    }
}
