import Foundation

/// Kdy jsem který pull request naposled viděl (#173).
///
/// Je to **stav aplikace, ne nastavení**, takže bydlí v předvolbách vedle poslední viděné verze
/// (#127), ne v `config.json` — tam by nikomu nic neřekl a dal by se rozbít.
///
/// Všechny návštěvy jsou v **jednom klíči** jako slovník, ne v klíči na PR. Klíč na PR by se
/// nedal projít, takže by v předvolbách zůstávala každá návštěva navždycky; takhle se dá při
/// zápisu uklidit. Cenou je, že se čte a zapisuje celý slovník naráz — u desítek PR je to nic.
struct VisitLedger {
    private let preferences: any PreferenceStoring

    /// Značka bydlí v předvolbách, ne v `config.json` — viz `PreferenceStoring`.
    private static let key = "pullRequests.lastVisits"

    /// Jak dlouho se návštěva pamatuje. PR, který se zavřel, se do seznamu nevrátí, takže by
    /// jeho záznam jinak ležel v předvolbách napořád.
    ///
    /// Devadesát dní je vědomě štědré: nejde o místo (je to pár set bajtů), ale o to, aby se
    /// slovník nerozrostl bez omezení. PR, ke kterému se vracím po třech měsících, je nový.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    init(preferences: any PreferenceStoring) {
        self.preferences = preferences
    }

    /// Co si o poslední návštěvě pamatujeme.
    ///
    /// Vedle času i **hlava, kterou jsem tehdy viděl**. Bez ní by se nové commity poznávaly
    /// jedině podle `TimelineEvent.at`, a to je u commitu **datum commitu, ne pushnutí**
    /// (`pushedDate` GitHub neplní, změřeno u #171). Po rebase nebo cherry-picku je tedy starší
    /// než moje návštěva a commit by z „od minule“ vypadl, přestože se na PR objevil teď —
    /// tedy přesně ten nebezpečný směr, kdy banner mlčí o změně kódu.
    struct Visit: Codable, Hashable, Sendable {
        let at: Date
        /// `nil` = návštěva proběhla dřív, než se stihl načíst detail PR.
        var head: String?
    }

    /// Kdy jsem PR viděl naposled a s jakou hlavou. `nil` = nikdy, což je **jiný stav** než
    /// „dávno“: nad prvním zobrazením se nemá co ukazovat, protože „od tvé poslední návštěvy“
    /// by tam znamenalo „od začátku věků“ a vypsalo by celou historii PR.
    func lastVisit(to pullRequest: PRIdentifier) -> Visit? {
        visits()[pullRequest.description]
    }

    /// Zapíše návštěvu a při té příležitosti zahodí, co se přežilo.
    ///
    /// `head` se **nepřepisuje na `nil`**: detail PR se načítá asynchronně, takže první zápis
    /// hlavu ještě nezná a druhý (po načtení) ji doplní. Kdyby ji každý zápis přepsal, ztratila
    /// by se pokaždé, když se na PR jen mrknu.
    func record(_ pullRequest: PRIdentifier, at now: Date, head: String? = nil) {
        var visits = visits().filter { now.timeIntervalSince($0.value.at) < Self.retention }
        let key = pullRequest.description
        visits[key] = Visit(at: now, head: head ?? visits[key]?.head)
        store(visits)
    }

    /// Rozbitá nebo chybějící hodnota znamená **prázdno**, ne pád.
    ///
    /// Je to bezpečný směr a schválně: prázdno vyjde jako „tenhle PR jsem nikdy neviděl“, takže
    /// se banner neukáže. Opačná volba — tvářit se, že návštěva byla — by ukázala změny proti
    /// času, který jsme si vymysleli. Uživatelova data se tím neztrácejí, protože žádná
    /// nezadal; je to odvozený stav, který se do jednoho otevření PR obnoví sám.
    private func visits() -> [String: Visit] {
        guard
            let raw = preferences.preference(forKey: Self.key),
            let data = raw.data(using: .utf8),
            let decoded = try? decoder.decode([String: Visit].self, from: data)
        else { return [:] }
        return decoded
    }

    private func store(_ visits: [String: Visit]) {
        guard
            let data = try? encoder.encode(visits),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        preferences.setPreference(raw, forKey: Self.key)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // ISO 8601, ne `timeIntervalSinceReferenceDate`: do předvoleb se člověk může podívat
        // a číslo mu tam neřekne nic.
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
