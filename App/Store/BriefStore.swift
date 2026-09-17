import Foundation

/// Poslední brief na disku (#516).
///
/// **Na disku, ne v paměti, a je to pojistka proti utrácení.** Režim `firstTickOfDay` se ptá, jestli
/// je dnešek už shrnutý — a kdyby se den držel jen v paměti, spustil by se brief po **každém
/// restartu** znovu. Je to tatáž úvaha jako u `AutoRunLedger`: pojistka, kterou obejde restart,
/// není pojistka.
///
/// Druhý důvod je, že po startu je co ukázat: blok s posledním briefem a razítkem `shrnuto 21:48`
/// je pravdivý stav, kdežto prázdný blok po restartu vypadá jako vypnutý brief.
///
/// Aktor ze stejného důvodu jako `AutoRunLedger` — čtení, přepsání a zápis jednoho souboru.
actor BriefStore {
    private let layout: CacheLayout
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    /// Brief, se kterým se pracuje. Disk je **záloha**, ne jediná kopie — tatáž úvaha jako
    /// u `AutoRunLedger.write`: trvale selhávající zápis nesmí znamenat, že se dnešek nikdy
    /// nezapíše a brief se pouští při každém tiku.
    private var cached: Brief?
    private var didRead = false

    init(layout: CacheLayout = .applicationSupport) {
        self.layout = layout
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Poslední brief. `nil` = ještě se neshrnovalo, nebo se soubor nedá přečíst.
    ///
    /// **Nečitelný soubor se bere jako prázdno**, ne jako chyba: nejhorší následek je jeden brief
    /// navíc, kdežto hlásit v okně poruchu kvůli rozbitému JSONu s odstavcem textu je hluk.
    func load() -> Brief? {
        if didRead { return cached }
        didRead = true
        cached = try? decoder.decode(Brief.self, from: Data(contentsOf: layout.briefFile))
        return cached
    }

    /// Uloží nový brief — **nejdřív do paměti, pak na disk**, jako `AutoRunLedger`.
    func save(_ brief: Brief) {
        cached = brief
        didRead = true
        try? FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        try? encoder.encode(brief).write(to: layout.briefFile, options: .atomic)
    }
}
