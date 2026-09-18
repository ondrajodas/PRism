import Foundation

/// Posledních deset **mých** odeslaných těl review na disku (#521) — vzorek hlasu pro osmou
/// session.
///
/// **Na disku, a je to podmínka, ne pohodlí.** Konverzace se nepersistuje (`Conversation`), takže
/// v paměti by z hlasu po restartu zbylo přesně tolik, kolik PR jsem si zrovna otevřel — a první
/// návrh review po startu aplikace by se psal neutrálně, i když těl review mám na GitHubu sto.
/// Je to tatáž úvaha jako u `BriefStore`: stav, který obejde restart, na svou otázku neodpovídá.
///
/// **Sbírá se čtením, ne zápisem.** Vzorky se berou z konverzací, které aplikace načte tak jako
/// tak — ne z vlastní evidence odeslaných review. Rozdíl je v tom, co je pravda: co leží na
/// GitHubu, je to, co jsem doopravdy odeslal, včetně pozdějších editací a review odeslaných
/// odjinud než z téhle aplikace.
///
/// Aktor ze stejného důvodu jako `BriefStore` — čtení, slití a zápis jednoho souboru, a přijít
/// k tomu můžou dvě načtené konverzace naráz.
actor ReviewVoiceLedger {
    private let layout: CacheLayout
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Vzorky, se kterými se pracuje. Disk je **záloha**, ne jediná kopie — tatáž úvaha jako
    /// u `BriefStore.save`: trvale selhávající zápis nesmí znamenat, že se hlas nikdy nesejde.
    private var cached: [ReviewVoiceSample]?

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Vzorky od nejnovějšího. Prázdné = nic se ještě nesešlo, nebo se soubor nedá přečíst.
    ///
    /// **Nečitelný soubor je prázdno, ne chyba.** Nejhorší následek je jedno tělo review napsané
    /// neutrálně — a pruh nad panelem to řekne. Hlásit poruchu kvůli rozbitému JSONu s cizí prózou
    /// by byl hluk nad review, které doběhlo v pořádku.
    func samples() -> [ReviewVoiceSample] {
        if let cached { return cached }
        let read = (try? decoder.decode([ReviewVoiceSample].self, from: Data(contentsOf: layout.reviewVoiceFile))) ?? []
        cached = read
        return read
    }

    /// Přidá, co dorazilo v konverzaci, a nechá si **nejnovějších `Policy.reviewVoiceLimit`**.
    ///
    /// Vrací se to, co po slití leží v ledgeru, aby volající nemusel čtení opakovat.
    ///
    /// **Nezapisuje se, když se nic nezměnilo.** Táž konverzace se načte při každém otevření PR,
    /// takže bezpodmínečný zápis by znamenal soubor přepsaný při každém kliknutí na řádek fronty.
    @discardableResult
    func record(_ fresh: [ReviewVoiceSample]) -> [ReviewVoiceSample] {
        let merged = Policy.mergedReviewVoice(samples(), adding: fresh)
        guard merged != cached else { return merged }
        cached = merged
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(merged).write(to: layout.reviewVoiceFile, options: .atomic)
        return merged
    }
}
