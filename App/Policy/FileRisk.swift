import Foundation

/// Jak riskantní je soubor v diffu (#506) — podle toho se řadí v itineráři.
///
/// **Je to pořadí čtení, ne vážnost změny.** Odpovídá na otázku „čím začít“, a ta má jedinou
/// rozumnou odpověď: tím, o čem už někdo něco řekl. Blokující nález je práce, kterou nejde
/// odložit; lock soubor o dvanácti stech řádcích je šum, který se prolistuje na konci.
///
/// Surové pořadí `rawValue` je **pořadí klasifikace**, ne pořadí kresby: `configuration` se
/// rozhoduje **dřív** než `added` a `other` (lock soubor přidaný v tomhle PR je pořád šum),
/// ale kreslí se **poslední** a složený do jedné položky. Viz `Policy.filesByRisk`.
enum FileRisk: Int, Comparable, Hashable, Sendable {
    /// Je v něm aspoň jeden blokující nález.
    case blocking = 0
    /// Nálezy má, ale žádný neblokuje.
    case finding = 1
    /// Visí na něm vlákno konverzace — někdo se na něj ptá a čeká na odpověď.
    case thread = 2
    /// Konfigurace a locky. **Klasifikuje se před `added` a `other`**, protože nový lock soubor
    /// je pořád lock soubor; nález nebo vlákno ho ale přebijí (proto je až čtvrtý).
    case configuration = 3
    /// Nový soubor. Nemá starou verzi, takže se čte celý — a to je jiná práce než čtení diffu.
    case added = 4
    /// Zbytek: upravený, smazaný, přejmenovaný soubor bez nálezu i bez vlákna.
    case other = 5

    static func < (left: Self, right: Self) -> Bool { left.rawValue < right.rawValue }

    /// V jakém pořadí se skupiny **kreslí**. Liší se od klasifikace jedinou věcí: konfigurace
    /// jde na konec, protože se do ní nekouká, dokud není zbytek hotový.
    static let drawingOrder: [Self] = [.blocking, .finding, .thread, .added, .other, .configuration]

    /// Nadpis skupiny v itineráři. Krátký — sloupec má 260 bodů a nadpis v něm stojí na řádce
    /// sám.
    var groupTitle: String {
        switch self {
        case .blocking: "Blokující"
        case .finding: "S nálezem"
        case .thread: "S vláknem"
        case .added: "Nové"
        case .other: "Ostatní"
        case .configuration: "Konfigurace a locky"
        }
    }
}

/// Jedna položka v seznamu souborů itineráře (#506).
///
/// Dvě podoby, protože konfigurace a locky se **skládají do jedné položky**: u dvanácti
/// `composer.lock`, `package-lock.json` a `phpunit.xml.dist` nese každý jednotlivý řádek stejnou
/// informaci („tohle číst nemusím“), takže by dvanáct řádků jen odtlačilo dolů to, co se číst má.
enum ItineraryFileItem: Identifiable, Hashable, Sendable {
    /// Jeden soubor.
    case file(FileDiff, risk: FileRisk)
    /// Konfigurace a locky složené dohromady, v pořadí podle cesty.
    case bundle([FileDiff])

    var id: String {
        switch self {
        case .file(let file, _): file.id
        // Pevný klíč, ne složený ze cest: skládaná položka je v seznamu právě jedna, a klíč
        // z obsahu by se při každém pushi měnil — tedy nová identita a rozbalení se zavře.
        case .bundle: "itinerary.bundle.configuration"
        }
    }

    /// Soubory, které položka drží. U jednoho souboru je to on sám.
    var files: [FileDiff] {
        switch self {
        case .file(let file, _): [file]
        case .bundle(let files): files
        }
    }

    var risk: FileRisk {
        switch self {
        case .file(_, let risk): risk
        case .bundle: .configuration
        }
    }
}

/// Skupina souborů jednoho rizika — nadpis a položky pod ním (#506).
///
/// **Identitou je riziko**, ne pořadí ani obsah: skupina je v seznamu nejvýš jedna na riziko,
/// takže se identita nemění tím, že do souboru přijde commit.
struct ItineraryFileGroup: Identifiable, Hashable, Sendable {
    let risk: FileRisk
    var items: [ItineraryFileItem]

    var id: FileRisk { risk }
}

extension Policy {
    /// Jak riskantní je jeden soubor. **Rozhoduje první podmínka, která platí** — pořadí je
    /// v `FileRisk`.
    ///
    /// - Parameters:
    ///   - markers: značky nálezů (`Policy.fileMarkers`), klíčované `displayPath`em. Odmítnuté
    ///     nálezy odfiltroval volající, jako u stromu (#113).
    ///   - threadPaths: cesty, na kterých visí vlákno.
    static func risk(
        of file: FileDiff,
        markers: [String: FileMarker],
        threadPaths: Set<String>
    ) -> FileRisk {
        let path = file.displayPath
        switch markers[path] {
        case .blocking: return .blocking
        case .findings: return .finding
        case nil: break
        }
        if threadPaths.contains(path) { return .thread }
        if isConfigurationPath(path) { return .configuration }
        if file.change == .added { return .added }
        return .other
    }

    /// Je to konfigurace nebo lock soubor?
    ///
    /// **Výčet jmen a přípon, ne heuristika.** „Vypadá to na konfiguraci“ se nedá napsat tak, aby
    /// to nesnědlo `docs/navrh.html` nebo `src/config.php`, tedy soubory, které se číst mají.
    /// Skládá se ze tří pravidel a všechna jsou vidět:
    ///
    /// 1. **Lock soubor** — jméno je v `lockFileNames`, nebo končí na `.lock`. Generuje ho
    ///    nástroj, takže se v něm nedá nic přehlédnout, protože se v něm nic nerozhoduje.
    /// 2. **Přípona z `configurationExtensions`** — `.json`, `.yml`, `.yaml`, `.toml`, `.ini`,
    ///    `.cfg`, `.plist`, `.xcconfig`, `.dist`. Pozor: `.xml` v seznamu **není**, protože se
    ///    v něm píše i kód (Android layouty, XSLT); `phpunit.xml.dist` chytí `.dist`.
    /// 3. **Tečkový soubor v kořeni jména** — `.gitignore`, `.editorconfig`, `.gitattributes`.
    ///
    /// Cesta se rozhoduje **podle poslední složky**, ne podle prefixu: `config/` v cestě
    /// neznamená nic (`config/routes.php` je kód).
    static func isConfigurationPath(_ path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let lower = name.lowercased()
        if lockFileNames.contains(lower) || lower.hasSuffix(".lock") { return true }
        if configurationExtensions.contains(where: { lower.hasSuffix($0) }) { return true }
        return lower.hasPrefix(".")
    }

    /// Jména lock souborů, která se nepoznají z přípony.
    static let lockFileNames: Set<String> = [
        "package-lock.json",
        "pnpm-lock.yaml",
        "package.resolved",
        "gemfile.lock",
        "podfile.lock",
    ]

    /// Přípony, po kterých je soubor konfigurace. **`.xml` tu schválně není** — viz
    /// `isConfigurationPath`.
    static let configurationExtensions: Set<String> = [
        ".json", ".yml", ".yaml", ".toml", ".ini", ".cfg", ".plist", ".xcconfig", ".dist",
    ]

    /// Soubory diffu seřazené podle rizika, s konfigurací složenou do jedné položky (#506).
    ///
    /// Uvnitř skupiny se řadí **podle cesty**, ne podle velikosti změny: pořadí se nemá měnit
    /// tím, že do souboru přijde commit — hledá se v tom seznamu očima a stěhující se řádky jsou
    /// horší než neoptimální pořadí.
    ///
    /// Skládaná položka vznikne, **až když je konfigurací víc než jedna** (`configurationBundleFloor`):
    /// nad jediným `composer.lock` by rozbalovací řádek `1 konfigurace a lock` byl klik navíc
    /// k témuž souboru.
    static func filesByRisk(
        _ files: [FileDiff],
        markers: [String: FileMarker] = [:],
        threadPaths: Set<String> = []
    ) -> [ItineraryFileItem] {
        var groups: [FileRisk: [FileDiff]] = [:]
        for file in files {
            groups[risk(of: file, markers: markers, threadPaths: threadPaths), default: []].append(file)
        }
        for (risk, group) in groups {
            groups[risk] = group.sorted { $0.displayPath < $1.displayPath }
        }
        return FileRisk.drawingOrder.flatMap { risk -> [ItineraryFileItem] in
            let group = groups[risk] ?? []
            guard risk == .configuration, group.count >= configurationBundleFloor else {
                return group.map { .file($0, risk: risk) }
            }
            return [.bundle(group)]
        }
    }

    /// Od kolika konfigurací se skládá jedna položka.
    static let configurationBundleFloor = 2

    /// Položky rozdělené do skupin s nadpisem, v tom pořadí, ve kterém přišly z `filesByRisk`.
    ///
    /// **Skládá se z hotového seznamu, ne z diffu znovu**: pořadí rozhodl `filesByRisk` a druhé
    /// rozdělení by se s ním mohlo rozejít. Prázdná skupina ve výsledku **není** — nadpis nad
    /// ničím je tvrzení, že tam něco je.
    static func itineraryGroups(_ items: [ItineraryFileItem]) -> [ItineraryFileGroup] {
        var groups: [ItineraryFileGroup] = []
        for item in items {
            if groups.last?.risk == item.risk {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append(ItineraryFileGroup(risk: item.risk, items: [item]))
            }
        }
        return groups
    }

    /// Popisek skládané položky: `4 konfigurace a locky`.
    static func configurationBundleLabel(count: Int) -> String {
        Plural.czech(count, one: "konfigurace a lock", few: "konfigurace a locky", many: "konfigurací a locků")
    }
}
