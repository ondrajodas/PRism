import Foundation

/// O čem už aplikace dala vědět (#335) — razítko **oznámení**, ne návštěvy.
///
/// Druhé razítko vedle `VisitLedger`, a je to podmínka, ne pohodlí: „naposled jsem se na PR
/// koukal“ a „naposled jsem o něm dal vědět“ jsou **dvě různé věci**, protože oznámením PR
/// nenavštívím. Bez tohohle razítka by „2 nové komentáře“ chodily při každé rozhlídce, dokud PR
/// neotevřu — tedy přesně ta otrava, po které si člověk notifikace vypne.
///
/// **Vlastní typ, ne pole ve `VisitLedger.Visit`.** Zápis návštěvy se děje při **každém** zobrazení
/// detailu (`noteVisit`), kdežto zápis oznámení jen po doručené notifikaci; jeden slovník se dvěma
/// významy znamená, že se ta dvě data dají posunout omylem naráz — a posunutá značka oznámení
/// umlčí hlášku o něčem, co jsem neviděl. Retence se zopakuje třemi řádky, splynutí typů by se
/// rozešlo potichu.
///
/// **V předvolbách, ne v cache**, ze stejného důvodu jako návštěvy: je to jedno datum na PR, ne
/// materiál review (razítko předání nese identity nálezů, a proto bydlí v cache — viz
/// `HandoffLedger`).
struct ActivityNoticeLedger {
    private let preferences: any PreferenceStoring

    private static let key = "pullRequests.lastActivityNotices"

    /// Jak dlouho se razítko pamatuje — **stejných devadesát dní jako u návštěv** (#173). PR, který
    /// se zavřel, se do seznamu nevrátí, takže by jeho záznam jinak ležel v předvolbách napořád.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    init(preferences: any PreferenceStoring) {
        self.preferences = preferences
    }

    /// Kdy přišlo to nejnovější, o čem se u toho PR hlásilo. `nil` = nehlásilo se nic.
    func lastNotice(for pullRequest: PRIdentifier) -> Date? {
        notices()[pullRequest.description]
    }

    /// Zapíše, o čem se dalo vědět, a při té příležitosti zahodí, co se přežilo.
    ///
    /// `announced` je **datum té nejnovější ohlášené položky**, ne „teď“ — a je to celý smysl
    /// parametru: kdyby se zapisoval čas doručení, propadl by komentář, který přišel mezi dotazem
    /// na konverzaci a zápisem razítka, protože by vyšel jako starší než značka.
    ///
    /// **Nikdy se neposouvá dozadu.** Rozhlídka se ptá i na PR, o kterých se hlásilo dřív, a když
    /// mezitím přišla jen starší položka (paginace, přepočet), nemá to udělat z ohlášené věci
    /// neohlášenou.
    func record(_ pullRequest: PRIdentifier, announced: Date, at now: Date) {
        var notices = notices().filter { now.timeIntervalSince($0.value) < Self.retention }
        let key = pullRequest.description
        notices[key] = max(announced, notices[key] ?? announced)
        store(notices)
    }

    /// Rozbitá nebo chybějící hodnota znamená **prázdno**, ne pád.
    ///
    /// Bezpečný směr je tady prázdno: vyjde z něj „o tomhle PR se ještě nehlásilo“, takže se
    /// nejhůř zopakuje jedna notifikace o komentáři, který jsem ještě neviděl. Opačná volba —
    /// tvářit se, že se hlásilo — by hlášku **spolkla**, a to se pozná až tím, že něco nepřišlo.
    private func notices() -> [String: Date] {
        guard
            let raw = preferences.preference(forKey: Self.key),
            let data = raw.data(using: .utf8),
            let decoded = try? decoder.decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private func store(_ notices: [String: Date]) {
        guard
            let data = try? encoder.encode(notices),
            let raw = String(data: data, encoding: .utf8)
        else { return }
        preferences.setPreference(raw, forKey: Self.key)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // ISO 8601 jako u návštěv: do předvoleb se člověk může podívat a číslo mu tam neřekne nic.
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
