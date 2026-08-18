import Foundation

/// Které zadání jsem už předal agentovi (#334) — razítko na pull request.
///
/// **V cache, ne v předvolbách.** Razítko nese identity předaných položek, a u nálezu je to
/// `Policy.key(of:)`, tedy věta revieweera; to je materiál review a ten bydlí v cache vedle
/// nálezů samotných, ne v `UserDefaults` mezi volbami okna. (Návštěvy PR jsou v předvolbách
/// schválně — `VisitLedger` drží dvě data a sha, ne obsah.)
///
/// **Jeden soubor, ne soubor na PR**: klíč na PR by se nedal projít, takže by v cache zůstávalo
/// každé razítko navždycky. Takhle se dá při zápisu uklidit. Cenou je, že se čte a zapisuje celý
/// slovník naráz — u desítek PR je to nic.
///
/// Aktor ze stejného důvodu jako `AnnouncedPullRequests`: čtení, změna a zápis jsou tři kroky nad
/// jedním souborem.
actor HandoffLedger {
    /// Jak dlouho se razítko pamatuje. PR, který se zavřel, se do seznamu nevrátí, takže by jeho
    /// razítko jinak leželo v cache napořád.
    ///
    /// Devadesát dní je vědomě štědré a je to tatáž hodnota jako u návštěv (#173): nejde o místo,
    /// ale o to, aby slovník nerostl bez omezení. Zadání, které jsem předal před třemi měsíci,
    /// o dnešním stavu PR neříká nic.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    private let layout: CacheLayout
    private let time: any TimeSource
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Razítka, se kterými se pracuje. `nil` = ještě se nečetla z disku.
    private var cached: [PRIdentifier: Handoff]?

    init(layout: CacheLayout = .applicationSupport, time: any TimeSource = SystemTimeSource()) {
        self.layout = layout
        self.time = time
        // ISO 8601 a odsazení jako u nálezů: je to osobní nástroj, data se čtou i očima.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Všechna razítka. Čte se **jednou při startu** — odznak i pilulka se pak ptají paměti
    /// (`AppStore.handoffStamps`), protože je čte SwiftUI při každém překreslení okna.
    func load() -> [PRIdentifier: Handoff] { read() }

    /// Zapíše předání a při té příležitosti zahodí, co se přežilo.
    ///
    /// Opakované předání téhož PR to předchozí **přepíše**: otázka je „co jsem poslal naposled“,
    /// takže historie by se musela ukazovat u zadání, ke kterému se nevztahuje — tatáž úvaha jako
    /// u `StoredRecheck`.
    func record(_ handoff: Handoff, for pullRequest: PRIdentifier) {
        let now = time.now
        var stamps = read().filter { now.timeIntervalSince($0.value.at) < Self.retention }
        stamps[pullRequest] = handoff
        write(stamps)
    }

    /// Rozbitý nebo chybějící soubor znamená **prázdno**, ne pád.
    ///
    /// Je to bezpečný směr: prázdno vyjde jako „nepředáno“, takže odznak svítí a panel nabídne
    /// sestavení znovu. Opačná volba — tvářit se, že předání proběhlo — by zhasla odznak nad prací,
    /// která leží. Nic se tím neztrácí, co by zadal uživatel: je to odvozený stav, který se prvním
    /// předáním obnoví.
    private func read() -> [PRIdentifier: Handoff] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: layout.handoffsFile),
              let stored = try? decoder.decode([PRIdentifier: Handoff].self, from: data)
        else {
            cached = [:]
            return [:]
        }
        cached = stored
        return stored
    }

    /// Zapisuje **nejdřív do paměti, pak na disk**, jako `AutoRunLedger`.
    ///
    /// Selhání zápisu se spolkne. Za běhu platí paměť; po restartu se razítko nenajde, takže se
    /// odznak rozsvítí a zadání se dá předat znovu — tedy stav před #334, ne nový problém.
    private func write(_ stamps: [PRIdentifier: Handoff]) {
        cached = stamps
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(stamps).write(to: layout.handoffsFile, options: .atomic)
    }
}
