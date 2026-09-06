import Foundation

/// Na co už agent na vlastním PR odpovídal (#510) — razítko **spuštění**, ne návštěvy ani
/// oznámení.
///
/// **Třetí razítko vedle `VisitLedger` a `ActivityNoticeLedger`, a je to podmínka, ne pohodlí.**
/// „Koukal jsem se“, „dal jsem o tom vědět“ a „pustil jsem na to agenta“ jsou tři různé věci:
/// přečtený komentář opravu neudělá a doručená notifikace taky ne. Kdyby se agent řídil razítkem
/// oznámení, nespustil by se **nikdy** u člověka, který má notifikace vypnuté; kdyby se řídil
/// návštěvou, přestal by se spouštět nad PR, na který se koukám.
///
/// **Chybějící razítko znamená ticho, ne „spusť to na celou historii“** — a proto se při prvním
/// setkání s pull requestem **zasadí** (`seed`) na to, co na něm už leží. Bez toho by aplikace po
/// startu pustila agenta na měsíc starou diskuzi, tedy na kód, který mezitím nikdo nemá před sebou.
///
/// **V předvolbách, ne v cache**, ze stejného důvodu jako obě předchozí: je to jedno datum na PR,
/// ne materiál review.
struct AgentFixLedger {
    private let preferences: any PreferenceStoring

    private static let key = "pullRequests.lastAgentFixes"

    /// Jak dlouho se razítko pamatuje — **stejných devadesát dní** jako u návštěv a oznámení
    /// (#173). PR, který se zavřel, se do seznamu nevrátí, takže by jeho záznam jinak ležel
    /// v předvolbách napořád.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    init(preferences: any PreferenceStoring) {
        self.preferences = preferences
    }

    /// Po jakou položku už agent na tom PR odpovídal. `nil` = nikdy, tedy ani zasazeno.
    func lastRun(for pullRequest: PRIdentifier) -> Date? {
        stamps()[pullRequest.description]
    }

    /// Zapíše, po co je vyřízeno, a při té příležitosti zahodí, co se přežilo.
    ///
    /// `handled` je **datum té nejnovější vyřízené položky**, ne „teď“ — a je to celý smysl
    /// parametru, přesně jako u `ActivityNoticeLedger`: kdyby se zapisoval čas spuštění, propadl by
    /// komentář, který přišel mezi dotazem na konverzaci a zápisem razítka, a agent by na něj
    /// nikdy nedošel.
    ///
    /// **Nikdy se neposouvá dozadu**, aby přepočet nebo paginace neudělaly z vyřízené věci
    /// nevyřízenou — tedy druhý běh za tytéž peníze.
    func record(_ pullRequest: PRIdentifier, handled: Date, at now: Date) {
        var stamps = stamps().filter { now.timeIntervalSince($0.value) < Self.retention }
        let key = pullRequest.description
        stamps[key] = max(handled, stamps[key] ?? handled)
        store(stamps)
    }

    /// Rozbitá nebo chybějící hodnota znamená **prázdno**, ne pád.
    ///
    /// Bezpečný směr je tady opačný než u oznámení, a proto to stojí za větu: prázdno znamená
    /// „razítko není“, tedy **ticho** (viz `AppStore.startAgentFix`), ne „spusť to na všechno“.
    /// U rozbitého souboru předvoleb se tak nejhůř zasadí razítko znovu a agent se pustí až na to,
    /// co přijde potom.
    private func stamps() -> [String: Date] {
        guard
            let raw = preferences.preference(forKey: Self.key),
            let data = raw.data(using: .utf8),
            let decoded = try? decoder.decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private func store(_ stamps: [String: Date]) {
        guard
            let data = try? encoder.encode(stamps),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        preferences.setPreference(raw, forKey: Self.key)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // ISO 8601 jako u návštěv a oznámení: do předvoleb se člověk může podívat a číslo mu tam
        // neřekne nic.
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
