import Foundation

extension Policy {
    /// Jeden odebraný evaluační zásobník AttributeGraphu, rozebraný na to, co se z něj dá počítat
    /// (#361).
    ///
    /// **Tři věci, každá odpovídá na jinou otázku.** `top` je atribut, který se počítal ve chvíli
    /// vzorku — tedy *co* se přepočítává. `root` je poslední rámec, tedy ten, kdo si o celou tu
    /// řadu řekl — *kdo to vyvolal*. `changed` jsou vstupy, u kterých graf hlásí, že se jejich
    /// hodnota **doopravdy změnila** — a to je jediný kandidát na odpověď „co ten atribut špiní“,
    /// který v zásobníku je.
    struct GraphStack: Equatable, Sendable {
        let top: String?
        let root: String?
        let changed: [String]
    }

    /// Rozebere výstup `stack/text` z `GraphProbe.stack()`.
    ///
    /// Formát je skutečný výstup AttributeGraphu (macOS 26), ne dohad:
    ///
    /// ```
    ///   #0: 90240 GeometryActionBinder<_GeometryActionModifier<CGRect>> -> ()
    ///   -- inputs:
    ///     89240[@120] DynamicBody<ViewBodyAccessor<ProbeRow>, MainThreadFlags> -> …, changed
    ///   --
    ///   #1: 13500 UnaryLayoutComputer<_FrameLayout> -> LayoutComputer
    /// ```
    ///
    /// **Bere se typ `self`, ne typ hodnoty** (`X -> Y`, tedy část před `->`): hledá se, který
    /// atribut se přepočítává, a to je `X`. Typ hodnoty je u nich často tentýž
    /// (`ViewGeometry`, `LayoutComputer`), takže by se z něj nedalo poznat, o který uzel jde.
    ///
    /// Rozděluje se přes `TextLines`, protože zakončení řádků nevybírá aplikace — text přichází
    /// z cizí knihovny (pravidlo z `CLAUDE.md`).
    static func graphStack(from text: String) -> GraphStack {
        var top: String?
        var root: String?
        var changed: [String] = []
        for line in TextLines.nonEmpty(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                // `#3: 3096 UnaryChildGeometry<_FrameLayout> -> ViewGeometry`
                guard let type = graphAttributeType(of: trimmed.drop(while: { $0 != " " })) else {
                    continue
                }
                if top == nil { top = type }
                // Kořen je **poslední** rámec, takže se přepisuje až do konce výpisu.
                root = type
            } else if trimmed.hasSuffix(", changed") {
                guard let type = graphAttributeType(of: trimmed) else { continue }
                changed.append(type)
            }
        }
        return GraphStack(top: top, root: root, changed: changed)
    }

    /// Řádky diagnostiky o grafu (#361) — jde **za** hlavní řádek úseku, každý s odsazením.
    ///
    /// Prázdné pole znamená, že v tom úseku nebylo o grafu co říct. Rozhoduje se to tady, ne
    /// v `RenderDiagnostics`: ze stejného důvodu jako u `diagnosticLine` — řádek je jediné, co
    /// z diagnostiky zbyde, takže musí být složený čistou funkcí, kterou jde otestovat bez
    /// hodin, souboru a runloopu.
    ///
    /// **Pořadí je od nejobecnějšího k nejkonkrétnějšímu**: počty háků (kolikrát se v tom úseku
    /// přepočítala která část), pak souhrn zásobníků (kdo si o to řekl a co se změnilo), pak jeden
    /// zásobník vypsaný **po rámcích**. Ten poslední je tam schválně: souhrn se dá číst rychle, ale
    /// příště se stejně bude hledat v tom, co souhrn zahodil.
    ///
    /// **Celý výpis se do souboru nevejde, a to je změřené, ne odhad.** AttributeGraph u rámce `#0`
    /// vypíše i **všechny jeho vstupy** a jména typů jsou generická jména celého podstromu — jeden
    /// takový řádek měl nad skutečným diffem v okně **1,5 kB** a blok jich měl desítky. Za hořící
    /// sekundu by to byly desítky kB, takže by strop 8 MB padl po pár minutách hoření — zrovna
    /// tehdy, když je záznam potřeba. Do souboru proto jdou **rámce a vstupy s příznakem
    /// `changed`**; ostatní vstupy jsou v tom výpisu šum a `changed` je jediné, co odpovídá na
    /// otázku „co ten atribut špiní“.
    static func graphDiagnosticLines(
        sites: [String: Int],
        stacks: [String],
        samples: Int
    ) -> [String] {
        var lines: [String] = []
        if !sites.isEmpty {
            let sorted = sites.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            lines.append("    graf: " + sorted.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        }
        guard samples > 0 else { return lines }
        let parsed = stacks.map(graphStack(from:))
        // **Dotazy i vzorky**, ne jedno číslo: dotaz, ze kterého nic nepřišlo, znamená, že se
        // v tom místě graf neaktualizoval — a to je informace, ne nula k zamlčení.
        var summary = "    zásobník: \(samples) dotazů, \(stacks.count) vzorků"
        summary += graphHistogram("kořen", parsed.compactMap(\.root))
        summary += graphHistogram("vrchol", parsed.compactMap(\.top))
        summary += graphHistogram("změněné vstupy", parsed.flatMap(\.changed))
        lines.append(summary)
        // Výpis jen z **prvního** vzorku: ostatní se od něj obvykle liší jen čísly atributů
        // a v souboru by z toho byly stovky řádků za sekundu.
        if let first = stacks.first { lines += graphStackDetail(of: first) }
        return lines
    }

    /// Rámce zásobníku a vstupy, které se změnily — každý odsazený a zkrácený.
    ///
    /// **Řádek se propustí jedině tehdy, když z něj rozbor umí vytáhnout typ** (nález Copilota
    /// na #397). Do té doby stačilo, že začíná `#` nebo končí `, changed`, takže po změně formátu
    /// (je privátní) by se do záznamu opisoval syrový text vydávaný za rámec — přitom o tomhle
    /// výpisu je slíbeno, že u cizího formátu **zmlkne**. Teď je to tatáž podmínka jako u histogramu.
    private static func graphStackDetail(of stack: String) -> [String] {
        TextLines.nonEmpty(stack).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") || trimmed.hasSuffix(", changed") else { return nil }
            guard graphAttributeType(of: trimmed.hasPrefix("#")
                ? trimmed.drop(while: { $0 != " " })[...]
                : trimmed[...]) != nil
            else { return nil }
            return "    " + shortened(trimmed)
        }
    }

    /// Strop na délku jednoho řádku o grafu. Vyjmenovaná mez, ne odhad: jména typů v grafu jsou
    /// generická jména celého podstromu a nejdelší naměřené mělo **1,5 kB**.
    ///
    /// Cena je, že dva různé dlouhé typy mohou v souhrnu spadnout do jednoho řádku. Je to vědomé:
    /// informace je v **hlavě** jména (`LazySubviewPlacements<…`), kdežto konec je obvykle výčet
    /// modifikátorů, který stejně nikdo nepřečte.
    static let graphLineLimit = 200

    private static func shortened(_ text: String) -> String {
        guard text.count > graphLineLimit else { return text }
        return text.prefix(graphLineLimit) + "…"
    }

    /// Kolik různých hodnot se do jednoho histogramu vejde. Vyjmenovaná mez, ne odhad (nález
    /// Copilota na #397): zkrácení jedné hodnoty nebrání tomu, aby jich osm vzorků nasypalo desítky
    /// — a to je při hoření zpátky u kilobajtů za sekundu. Šest je tolik, kolik se z histogramu dá
    /// přečíst; co se nevejde, se **přizná** počtem, ne zamlčí.
    static let graphHistogramLimit = 6

    /// `nejčastější=3 druhý=1` s popiskem, nebo prázdno, když není co ukázat.
    ///
    /// Řadí se **podle počtu**, protože se hledá to, co se opakuje; při shodě podle jména, ať jsou
    /// dva soubory ze dvou sezení srovnatelné.
    private static func graphHistogram(_ label: String, _ values: [String]) -> String {
        guard !values.isEmpty else { return "" }
        let counts = values.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let sorted = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        let shown = sorted.prefix(graphHistogramLimit)
        var text = ", \(label) " + shown.map { "\(shortened($0.key))=\($0.value)" }.joined(separator: " ")
        if sorted.count > shown.count { text += " (+\(sorted.count - shown.count) dalších)" }
        return text
    }

    /// Typ atributu z řádku zásobníku: to, co stojí mezi číslem uzlu a `->`.
    ///
    /// `nil` u řádku, který takhle nevypadá — formát je cizí a může se změnit, a v takovém případě
    /// má souhrn zmlknout, ne vypsat půlku řádku jako jméno typu.
    private static func graphAttributeType<S: StringProtocol>(of line: S) -> String? {
        guard let arrow = line.range(of: " -> ") else { return nil }
        let head = line[line.startIndex..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        // `89240[@120] DynamicBody<…>` — číslo uzlu i jeho `[@offset]` jsou před první mezerou.
        guard let space = head.firstIndex(of: " ") else { return nil }
        let type = head[head.index(after: space)...].trimmingCharacters(in: .whitespaces)
        return type.isEmpty ? nil : type
    }
}
