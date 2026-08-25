import SwiftUI

/// Hlavička souboru v diffu (`.fhead`, #219).
///
/// Celá je tlačítko, ne jen šipka — na GitHubu se kliká kamkoli do řádku a trefit se do šipky
/// u padesáti souborů je práce navíc.
struct DiffFileHeaderView: View {
    let file: FileDiff
    let isFolded: Bool
    /// Skupiny nálezů patřící k tomuhle souboru. Vybral je volající — nález umí přijít pod
    /// **starou** cestou přejmenovaného souboru, a to je jeho starost, ne hlavičky.
    let findings: [FindingGroup]
    let blockingCategories: Set<String>
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: file.displayPath))
        .accessibilityHint(isFolded ? "Rozbalí diff souboru" : "Sbalí diff souboru")
    }

    private var content: some View {
        HStack(spacing: 9) {
            Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .frame(width: 10)
            FilePathText(path: file.displayPath)
            if let badge = badge {
                pill(badge, color: Palette.ink2)
            }
            if file.change == .renamed, let oldPath = file.oldPath {
                Text(verbatim: "← \(oldPath)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 9)
            findingsPill
            DiffCounts.text(additions: file.additions, deletions: file.deletions)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        // Ukotvená hlavička jede přes obsah, takže pod ní musí být neprůhledné pozadí.
        .background(Palette.chrome)
        // **Ne `Divider()`.** Ten si orientaci bere z okolní osy a v `overlay` žádná není,
        // takže se vykreslí **svisle** — pod hlavičkami tedy nikdy nebyla čára, kterou tam
        // tenhle kód chtěl, ale svislá čárka uprostřed. Dokud mezi hlavičkami byly řádky
        // diffu, ztrácely se; po sbalení všech souborů (#59) se poskládaly do jedné čáry.
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.lineSoft).frame(height: 1)
        }
    }

    /// Kolik nálezů v souboru je — kapsle, jak ji má návrh (`.pill`).
    ///
    /// Ukazuje se **vždycky**, ne jen u sbaleného. U sbaleného je to nutnost — zavřený soubor
    /// s nevyřízeným nálezem by se dal zapomenout a tabulka nálezů je jiná obrazovka. U
    /// rozbaleného to není šum, ale zkratka: projedu hlavičky a vím, kde nálezy jsou, aniž bych
    /// scrolloval obsahem.
    ///
    /// Počítá **platné** nálezy (#113). Odznak je zkratka „kde je co vyřídit“, takže odmítnutý
    /// nález v něm nemá co dělat — a hlavně by u sbaleného souboru svítil červeně nad něčím, co
    /// jsem už posoudil. Nemizí tím nic: bublina u řádku i řádek v tabulce zůstávají.
    @ViewBuilder private var findingsPill: some View {
        let counts = Policy.fileFindings(in: findings, categories: blockingCategories)
        if let text = Self.badgeLabel(blocking: counts.blocking, total: counts.total) {
            pill(text.label, color: text.isBlocking ? Palette.crit : Palette.ink2)
        }
    }

    /// Co je v kapsli napsané. **Blokující má vlastní slovo, ne jen barvu** (`1 blokuje`, jak to
    /// má návrh): kapsle je tvarem k nerozeznání od odznaku změny hned vedle, takže barva sama by
    /// byla jediný rozdíl — a na tu se nedá spolehnout. Je to tatáž úvaha, proč je ve stromu
    /// souborů obarvená **ikona**, ne jen puntík.
    ///
    /// `nil` = v souboru není co vyřídit a kapsle se nekreslí. Počty rozhoduje `Policy`, tady se
    /// z nich skládá jen věta.
    static func badgeLabel(blocking: Int, total: Int) -> (label: String, isBlocking: Bool)? {
        guard total > 0 else { return nil }
        guard blocking > 0 else {
            return (Plural.czech(total, one: "nález", few: "nálezy", many: "nálezů"), false)
        }
        // Sloveso se skloňuje: „2 blokuje“ je špatně česky, „5 blokují“ taky.
        return (Plural.czech(blocking, one: "blokuje", few: "blokují", many: "blokuje"), true)
    }

    /// Kapsle z návrhu: mono, 10,5 bodu, podklad je 15% barva popisku. Sazba je v `designPill`
    /// (#348); `monospacedDigit()` odsud **odešlo jako nadbytečné** — mono řez má cifry stejně
    /// široké sám a nastavené písmo by ho přebilo.
    private func pill(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .designPill(tint: color, background: color.opacity(0.15))
            .lineLimit(1)
    }

    private var badge: String? {
        if file.isBinary { return "binární" }
        switch file.change {
        case .added: return "nový"
        case .deleted: return "smazaný"
        case .renamed: return "přejmenovaný"
        case .modified: return nil
        }
    }
}

/// Cesta souboru: složka tlumeně, jméno tučně (`fhead .path`, #219).
///
/// Do #219 nesla hlavička celou cestu jedním řezem a v užším místě se ořezávala jako celek —
/// u dvou souborů téhož jména tedy nešlo poznat, který je který. Strom vedle na to odpovídat
/// nemá: dá se složit, a v pohledu vedle sebe se skládá sám (#188).
struct FilePathText: View {
    let path: String

    var body: some View {
        let parts = Self.parts(of: path)
        HStack(spacing: 0) {
            if !parts.directory.isEmpty {
                // Složka se ořezává **zepředu** a ustoupí první: nese ji poslední část
                // (`…/Vault/`), kdežto začátek cesty je u většiny PR pořád stejný. Je to
                // tatáž úvaha jako ve stromu souborů (#197).
                Text(verbatim: parts.directory)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            // Jméno má přednost v rozvržení, takže zůstane celé i v úzkém sloupci — právě kvůli
            // němu se cesta rozdělila na dva kusy.
            Text(verbatim: parts.name)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    /// `src/Vault/SecretClient.php` → (`src/Vault/`, `SecretClient.php`).
    ///
    /// Lomítko zůstává u **složky**: vizuálně patří k ní a jméno má být tučné samo o sobě.
    /// Cesta bez lomítka je celá jméno; cesta končící lomítkem (složka, která se v diffu
    /// neobjeví, ale typ ji nezakazuje) taky — prázdné jméno by hlavičku nechalo bez popisku.
    static func parts(of path: String) -> (directory: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return ("", path) }
        let start = path.index(after: slash)
        guard start < path.endIndex else { return ("", path) }
        return (String(path[..<start]), String(path[start...]))
    }
}
