import Foundation

/// Kapsle druhu změny v hlavičce souboru (#525, zákres sekce 59).
///
/// **Dvě hodnoty, ne jen popisek**: `změna chování` je to jediné slovo z pěti, kvůli kterému se
/// do souboru kouká napřed, takže má akcent — a zbytek je tichý. Barva se tím rozhoduje **jednou
/// pro kresbu**, ne pětkrát ve `switch`i ve view.
struct ChangeKindChip: Hashable, Sendable {
    /// Co je v kapsli napsané. Česky, malými písmeny — jako ostatní kapsle v té hlavičce.
    let label: String
    /// Má se kreslit akcentem? `false` = nejtišší tón v řádku (`--ink-3`, jako `.pill.quiet`).
    let isProminent: Bool
}

extension Policy {
    /// Jak se druh změny kreslí v hlavičce souboru (#525).
    ///
    /// **Popisky jsou tady, ne na `FileChangeKind`**, a je to tatáž dělba jako u `FileRisk`
    /// naopak: `rawValue` enumu jde do promptu i na disk (tedy anglicky), kdežto tohle je text
    /// pro okno a rozhoduje se z něj i barva. Vyčerpává se výčtem v testu, takže nový druh
    /// nemůže projít bez popisku.
    ///
    /// Znění je ze zákresu doslova: `změna chování`, `refaktor`, `test`, `konfigurace`,
    /// `generované`.
    static func changeKindChip(of kind: FileChangeKind) -> ChangeKindChip {
        switch kind {
        case .behaviour: ChangeKindChip(label: "změna chování", isProminent: true)
        case .refactor: ChangeKindChip(label: "refaktor", isProminent: false)
        case .test: ChangeKindChip(label: "test", isProminent: false)
        case .configuration: ChangeKindChip(label: "konfigurace", isProminent: false)
        case .generated: ChangeKindChip(label: "generované", isProminent: false)
        }
    }

    /// Celá anotace jednou větou — pro odečítač obrazovky (#525).
    ///
    /// **Skládá se tady, ne ve view**: v okně stojí věta a zdroj jako dva různě tiché kusy jednoho
    /// odstavce, kdežto odečítač dostane jednu větu. Zdroj se **nevynechává** — je to doklad, ze
    /// kterého se pozná, jestli anotace stojí na commitu, nebo na dohadu.
    static func annotationSpeech(of annotation: HunkAnnotation) -> String {
        guard let source = annotation.source, !source.isEmpty else { return annotation.why }
        return "\(annotation.why) — \(source)"
    }

    /// Co o anotacích říká stavový řádek (#525) — `Anotace · 4 věty · proti 4f2ac91`.
    /// `nil` = **nepíše se nic**.
    ///
    /// **Mluví o datech, ne o kresbě.** Věty se v diffu dají schovat přepínačem `Anotace u hunků`;
    /// tenhle údaj se tím neřídí, protože odpovídá na otázku „je tenhle diff popsaný, a proti čemu“
    /// — a ta má stejnou odpověď se schovanými větami i bez nich.
    ///
    /// **`proti <hlava>` je ta polovina, kvůli které to stojí za pruh.** Anotace se páruje
    /// **pořadím hunku**, takže platí jedině proti jedné hlavě (tvrdá podmínka č. 5) — a bez
    /// vypsané hlavy by se nedalo poznat, jestli se dívám na popis dnešního diffu, nebo na prázdno
    /// po pushi. Neplatný záznam sem **nedojde**: vybírá ho `Policy.annotations(of:head:)`.
    ///
    /// **Záznam bez jediné věty se nepíše.** `Anotace · 0 vět` by v pruhu tvrdilo, že je co číst;
    /// že session doběhla a nic nenapsala, patří do dráhy `anotace` v tabu `Průběh`, kde se o běhu
    /// mluví celou větou.
    static func annotationStatus(of stored: StoredAnnotations?) -> String? {
        guard let stored, !stored.hunks.isEmpty, !stored.headSha.isEmpty else { return nil }
        let count = Plural.czech(stored.hunks.count, one: "věta", few: "věty", many: "vět")
        return "Anotace · \(count) · proti \(stored.headSha.prefix(7))"
    }

    /// Celá věta do nápovědy nad tím údajem. **Že je to psané session, musí být napsané** — jinak
    /// se věty nad hunky čtou jako něco, co ověřil člověk.
    static let annotationStatusHelp = """
        Věty proč u hunků napsala jedna session nad touhle hlavou PR.
        Po pushi přestanou platit a v diffu se nenakreslí — hunky se přečíslují, takže by ukazovaly vedle.
        """
}
