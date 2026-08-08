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

    /// Kdy jsem PR viděl naposled. `nil` = nikdy, což je **jiný stav** než „dávno“: nad prvním
    /// zobrazením se nemá co ukazovat, protože „od tvé poslední návštěvy“ by tam znamenalo
    /// „od začátku věků“ a vypsalo by celou historii PR.
    func lastVisit(to pullRequest: PRIdentifier) -> Date? {
        visits()[pullRequest.description]
    }

    /// Zapíše návštěvu a při té příležitosti zahodí, co se přežilo.
    func record(_ pullRequest: PRIdentifier, at now: Date) {
        var visits = visits().filter { now.timeIntervalSince($0.value) < Self.retention }
        visits[pullRequest.description] = now
        store(visits)
    }

    /// Rozbitá nebo chybějící hodnota znamená **prázdno**, ne pád.
    ///
    /// Je to bezpečný směr a schválně: prázdno vyjde jako „tenhle PR jsem nikdy neviděl“, takže
    /// se banner neukáže. Opačná volba — tvářit se, že návštěva byla — by ukázala změny proti
    /// času, který jsme si vymysleli. Uživatelova data se tím neztrácejí, protože žádná
    /// nezadal; je to odvozený stav, který se do jednoho otevření PR obnoví sám.
    private func visits() -> [String: Date] {
        guard
            let raw = preferences.preference(forKey: Self.key),
            let data = raw.data(using: .utf8),
            let decoded = try? decoder.decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private func store(_ visits: [String: Date]) {
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
