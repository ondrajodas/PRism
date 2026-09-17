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
    /// Stav značky `Prošlo` (#500). `nil` = tahle obrazovka značky nemá (diff commitu, rozsahový
    /// diff) a zaškrtávátko se **nekreslí vůbec** — zašedlé by slibovalo akci, která tam není.
    var read: FileReviewState?
    var toggleRead: (() -> Void)?
    /// Otevření souboru v editoru (#530). `nil` = **není zvolený editor**, takže se tlačítko
    /// nekreslí vůbec — ne zašedle, viz `EditorActions`.
    var editor: EditorActions?
    /// Druh změny z anotací (#525). `nil` = **kapsle se nekreslí**: session soubor nepopsala,
    /// anotace neplatí pro dnešní hlavu, nebo je to obrazovka, která anotace nemá (diff commitu,
    /// rozsahový diff). Vybírá ho `Policy.changeKind(of:in:)`; **ze jména souboru se druh
    /// neodvozuje** — `generované` u `composer.lock` je dohad, ne to, co někdo přečetl.
    var changeKind: FileChangeKind?

    /// Hledání v tomhle diffu (#152) — **prostředím, ne parametrem**: počet výskytů se mění při
    /// každém písmenu, takže předávat ho argumentem by znamenalo přeložit při každém znaku tělo
    /// celého diffu. Takhle se překreslí jen hlavičky. `nil` = v tomhle diffu se nehledá.
    @Environment(DiffSearchState.self) private var search: DiffSearchState?

    var body: some View {
        // **Řádek se od #500 dělí na dvě tlačítka**: sbalení bere všechno až po zaškrtávátko
        // a zaškrtávátko svůj kousek vpravo. Tlačítko v tlačítku je v SwiftUI přesně ten druh
        // věci, u které se nedá spolehnout, kdo klik dostane — a pravidlo z #219 („kliká se
        // kamkoli do řádku“) tím zůstává v platnosti pro celou plochu kromě těch pár desítek
        // bodů, kde je jiná akce.
        HStack(spacing: 9) {
            Button(action: toggle) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: file.displayPath))
            .accessibilityHint(isFolded ? "Rozbalí diff souboru" : "Sbalí diff souboru")
            // **Mimo tlačítko sbalení**, ze stejného důvodu jako zaškrtávátko o řádek níž:
            // tlačítko v tlačítku je v SwiftUI přesně ten druh věci, u které se nedá spolehnout,
            // kdo klik dostane. Smazaný soubor tlačítko **dostane taky** — že po něm na disku nic
            // nezůstalo, se pozná až sáhnutím na disk a hláška o tom je poctivější než chybějící
            // tlačítko u jednoho řádku z padesáti.
            if let editor {
                editor.headerButton(path: file.displayPath)
            }
            if let read, let toggleRead {
                DiffFileReadToggle(state: read, toggle: toggleRead)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

    private var content: some View {
        HStack(spacing: 9) {
            Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .frame(width: 10)
            // Prošlý soubor má jméno tlumené (`.fhead.rv-done .path b` v návrhu): hlavička
            // zůstává čitelná, ale oko po ní neklouže jako po tom, co ještě čeká.
            FilePathText(path: file.displayPath, isMuted: read?.isRead == true)
            if let badge = badge {
                pill(badge, color: Palette.ink2)
            }
            changeKindPill
            stalePill
            if file.change == .renamed, let oldPath = file.oldPath {
                Text(verbatim: "← \(oldPath)")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            searchPill
            Spacer(minLength: 9)
            findingsPill
            DiffCounts.text(additions: file.additions, deletions: file.deletions)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Druh změny (#525) — kapsle vedle odznaku změny, jak ji má zákres (sekce 59).
    ///
    /// **`změna chování` akcentem, zbytek nejtišším tónem v řádku** (`--ink-3`, tedy `.pill.quiet`
    /// z návrhu). Je to tvrzení **session**, ne gitu: `nový` a `binární` vedle jsou fakta z diffu,
    /// tohle je čtení někoho jiného, takže nemá být hlasitější než ona. Výjimka je jediná a je to
    /// ta, kvůli které celá kapsle existuje — do souboru, který mění chování, se kouká napřed.
    ///
    /// **Barvu vydává `Policy`**, ne `switch` tady: kdo přidá šestý druh, projde testem popisků
    /// a barvu dostane spolu s ním.
    @ViewBuilder private var changeKindPill: some View {
        if let changeKind {
            let chip = Policy.changeKindChip(of: changeKind)
            pill(chip.label, color: chip.isProminent ? Palette.accent : Palette.ink3)
        }
    }

    /// `změněno od prošlého` (#500) — kapsle u cesty, v okrové `--stale`, tedy tam a v té barvě,
    /// jakou má návrh (sekce 40).
    ///
    /// **Kapsle, ne jen jiná barva zaškrtávátka**: samotné `Prošlo znovu` vedle by se dalo
    /// přečíst jako nabídka, ne jako to, že přečtená verze už v souboru není. Nic se nepokazilo,
    /// takže ne červená.
    @ViewBuilder private var stalePill: some View {
        if let read, let text = Policy.changedSinceReadLabel(of: read) {
            pill(text, color: Palette.stale)
        }
    }

    /// Kolik výskytů hledání soubor má (#152) — kapsle vlevo u cesty, jak ji má návrh (sekce 39).
    ///
    /// **Akcentová, ne v barvě nálezu**: `find` znamená nález a odznak nálezu visí v téže hlavičce
    /// o dva prvky vedle. Kreslí se jedině s **otevřeným** pruhem: zavřené hledání o souboru nic
    /// netvrdí, protože zvýraznění v něm zhaslo.
    ///
    /// U **sbaleného** souboru je to nutnost — hledání se v něm počítá (sbalení je stav okna, ne
    /// stav dat), takže bez kapsle by nebylo z čeho poznat, že v něm něco je. U rozbaleného je to
    /// zkratka „ve kterém souboru to je“, tatáž úvaha jako u kapsle s nálezy.
    @ViewBuilder private var searchPill: some View {
        if let search, search.isOpen,
           let text = Policy.fileSearchLabel(search.counts[file.displayPath] ?? 0) {
            pill(text, color: Palette.accent)
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
    /// Prošlý soubor (#500) — jméno se tlumí z `ink` na `ink2` a z 620 na 500, jak to má návrh
    /// (`.fhead.rv-done .path b`). Složka zůstává, jaká byla: tlumená je už tak.
    var isMuted = false

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
                .fontWeight(isMuted ? .medium : .semibold)
                .foregroundStyle(isMuted ? Palette.ink2 : Palette.ink)
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
