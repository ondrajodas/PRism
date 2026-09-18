import Foundation

/// Co si automat o **těchhle** nálezech rozhodl (#520) — razítko návrhu review.
///
/// **Bydlí na `ReviewRecord`u, tedy u klíče `(PR, headSha)`**, a je to tatáž volba jako
/// u kontroly nálezů (#150): je to tvrzení o těch konkrétních nálezech, takže patří k nim.
/// Vedlejší účinek je zrovna ten, který tvrdá podmínka č. 5 chce — **jak se hlava pohne, návrh
/// zhasne sám**: nový commit znamená nový záznam a v něm razítko není, takže z okna zmizí
/// pilulka ve frontě, pruh v panelu i značky `sporné` u nálezů. Žádná další kontrola na to
/// není potřeba a žádná se na to nedá zapomenout.
///
/// **Neukládá se sem to, co se převzalo, ale kolik.** Převzaté nálezy jsou vidět jako komentáře
/// v rozdělaném review (`ReviewDraftComment.origin`), takže druhý seznam týchž vět by byl stav,
/// který se umí rozejít s tím, co je v panelu doopravdy.
struct StoredAutoDraft: Codable, Hashable, Sendable {
    /// Kdy automat návrh složil. Píše se do pruhu v panelu (`Návrh připravený automatem · 21:52`).
    let at: Date
    /// Kolik nálezů si vzal do draftu.
    let adopted: Int
    /// Které nechal a proč. Klíčem je `Policy.key(of:)`, tedy **tentýž klíč jako u odmítnutí**
    /// (#113) — dva klíče na jeden nález by znamenaly, že se značka `sporné` po dalším běhu
    /// rozpáruje a potichu zmizí.
    let contested: [FindingKey: AutoDraftDoubt]
    /// Co osmá session udělala s **tělem** review (#521). `nil` = nepsalo se — buď se ještě
    /// nedoběhlo, nebo session není zapojená.
    ///
    /// **Volitelné pole, ne druhý soubor**, a je to rozhodnutí: tělo návrhu platí pro **tytéž
    /// nálezy** jako razítko, takže mu má zhasnout naráz s ním. Druhé razítko vedle by znamenalo
    /// druhé místo, kde se dá zapomenout na hlavu — a pruh by po pushi mluvil o hlasu nad panelem,
    /// ve kterém už nic není.
    var body: AutoDraftBody?

    init(
        at: Date,
        adopted: Int,
        contested: [FindingKey: AutoDraftDoubt],
        body: AutoDraftBody? = nil
    ) {
        self.at = at
        self.adopted = adopted
        self.contested = contested
        self.body = body
    }

    /// Kolik nálezů měl návrh v ruce — `z 5 nálezů 3 převzaty, 2 sporné`.
    ///
    /// **Odmítnuté se nepočítají**: o nich je rozhodnuto, takže se do věty o tom, co návrh
    /// zvažoval, nepletou.
    var considered: Int { adopted + contested.count }
}
