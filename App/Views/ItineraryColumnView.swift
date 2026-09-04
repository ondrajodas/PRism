import SwiftUI

/// Levý sloupec záložky pull requestu: **hlavička, proužek podílu a itinerář** (#506).
///
/// **Od #506, druhého kola, stojí vedle všech tabů, ne uvnitř `Změněných souborů`** (připomínka
/// z proklikání). Do té doby byl součástí obsahu tabu, takže překliknutím na `Kontroly` zmizel —
/// a mizel právě ve chvíli, kdy podle něj člověk někam odešel. Itinerář, ze kterého se nedá vrátit,
/// není průvodce; proto ho hostí `PullRequestDetailView` a stojí vlevo od pruhu obsahu, ať je vidět
/// kterýkoli tab.
///
/// **Rozložený sloupec a složený proužek jsou dva typy, ne jedno tělo s `if`em**
/// (`ItineraryRailView` níž) — a je to **předfiltr, ne estetika**: od #506/2 se tenhle uzel skládá
/// při každém průchodu tělem detailu a v **každém** tabu, kdežto složený proužek potřebuje jedinou
/// hodnotu (počet souborů). Kdyby zastávky a soubory byly parametry jednoho typu, skládaly by se
/// i tehdy, když se z nich nekreslí nic. Dva typy k tomu znamenají, že **každý vstup má význam**:
/// tady jsou všechny povinné, protože se všechny kreslí.
///
/// **Položky a značky se sem předávají složené**: skládá je `Policy` v detailu a značky čte i
/// pořadí souborů podle rizika, takže by dvě složení znamenala dvě odpovědi na jednu otázku —
/// tatáž úvaha jako u `marginCards`.
struct ItineraryColumnView: View {
    /// Položky seznamu souborů — `Policy.filesByRisk`.
    let items: [ItineraryFileItem]
    /// Zastávky a co se stane po kliknutí na ně. Popisek hlavičky (`ITINERÁŘ · 4 Z 11 · 10 MIN`)
    /// a podíl do proužku se z nich **odvozují** — jsou to dvě podoby jednoho počítadla, takže dvě
    /// vstupní hodnoty by se daly nastavit nesouhlasně.
    let itinerary: ItineraryActions
    var markers: [String: FileMarker] = [:]
    var readStates: [String: FileReviewState] = [:]
    /// Složit sloupec — šipkou v hlavičce. Zavírat jedině z lišty nad diffem by znamenalo hledat
    /// tlačítko na druhém konci okna, než u kterého člověk zrovna je, a od #506/2 by to navíc bylo
    /// tlačítko, které v pěti z osmi tabů není.
    let collapse: () -> Void
    let jump: (FileDiff) -> Void

    /// Rozložený sloupec. Šířka 260 bodů je z návrhu (sekce 47; do #506 to bylo 210 podle #197).
    var body: some View {
        VStack(spacing: 0) {
            // Hlavička jako u panelu vpravo: popisek z návrhu a šipka, kterou se sloupec zavře.
            HStack(spacing: 8) {
                Text(verbatim: heading.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(action: collapse) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Policy.shortcutHelp("Složit itinerář", .itinerary))
                .accessibilityLabel("Složit itinerář")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }

            progress

            ReviewItineraryView(
                items: items,
                itinerary: itinerary,
                markers: markers,
                readStates: readStates,
                jump: jump
            )

            keys
        }
        .frame(width: Self.width)
        .background(Palette.chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
    }

    /// Popisek hlavičky — `Policy` ho skládá z počítadla, sloupec ho jen sází.
    private var heading: String { Policy.itineraryHeading(itinerary.progress) }

    /// Patka s klávesami (#507) — `␣ další zastávka · ⌥↓ další nález · ⌥V prošlo`.
    ///
    /// **Popisky se odvozují z katalogu** (`Policy.itineraryKeyHints`), nikdy se neopisují vedle
    /// klávesy (#441). Sloupec z nich jen sází kapsle.
    ///
    /// **Jedna řádka, jak to má návrh, a vešla se až na druhý pokus** (#507). Sázka je 9,5 b
    /// a mezera mezi prvky **3 body**: s pěti to dá 236,5 b proti 234 b, které ve sloupci po
    /// odsazení zbývají — a přetečení se neprojeví přetékajícím textem, ale **oříznutým prvním
    /// popiskem** (`další zast…`), takže se to pozná jedině z renderu. Se třemi je to 222,5 b,
    /// tedy 11,5 b rezervy. Mezery mezi prvky (sedm) tady stojí víc než odsazení kapslí, takže
    /// je to ta hodnota, kterou se platí.
    private var keys: some View {
        let hints = Policy.itineraryKeyHints
        return HStack(spacing: 3) {
            ForEach(hints) { hint in
                // Oddělovač **mezi** dvojicemi, ne za každou: `·` na konci řádky je značka, po
                // které nic nenásleduje. Rozhoduje o něm identita první položky, ne index —
                // pole tuplů z `enumerated()` je v tomhle repu vzor, který se neopakuje (#361).
                if hint.id != hints.first?.id {
                    Text(verbatim: "·")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.ink3)
                }
                Text(verbatim: hint.key)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 4)
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1) }
                Text(verbatim: hint.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        // Je to legenda, ne ovládání — VoiceOver ji přečte jako jednu větu, ne jako šest útržků.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Klávesy itineráře")
    }

    /// Tenký proužek podílu pod hlavičkou (#500, od #506 nad celým itinerářem) — 3 body,
    /// `--ok` na `--panel-3`, jak ho má návrh.
    ///
    /// **Nekreslí se, dokud není hotové nic**: prázdná linka nad nezapočatým PR je stálý prvek
    /// bez informace. `Policy` na to odpovídá `nil`em, ne nulou — tady se jen rozhoduje, co to
    /// znamená v kresbě.
    @ViewBuilder private var progress: some View {
        if let share = itinerary.progress.share {
            // **Šířka se počítá, nevyjednává** (#220): proužek zná šířku sloupce, takže se podíl
            // dá vyjádřit rámečkem, ne pružností.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Palette.ok)
                    .frame(width: (Self.width - 26) * share)
                Spacer(minLength: 0)
            }
            .frame(height: 3)
            .background(Palette.raised)
            .clipShape(.rect(cornerRadius: 2))
            .padding(.horizontal, 13)
            .padding(.top, 7)
            .accessibilityLabel(Text(verbatim: heading))
        }
    }

    /// **Čte se z `Policy`**, protože podle týchž čísel se rozhoduje, jestli se kolona kódu vejde
    /// (`Policy.diffSideColumns`) — dvě pravdy o jedné šířce by se rozešly při první úpravě.
    static let width = Policy.treeColumnWidth(expanded: true)
}

/// Složený levý sloupec — **proužek 34 bodů, ne zmizelý sloupec** (#197, #506).
///
/// Kolik souborů PR mění, je ta první otázka nad diffem, takže se na ni musí dát odpovědět i po
/// složení: na proužku je proto počet, ne jen ikona.
struct ItineraryRailView: View {
    /// Kolik souborů PR mění. **`nil` = diff se ještě nenačetl**, a pak se počet nekreslí vůbec:
    /// `0 souborů` na proužku by tvrdilo „tenhle pull request nic nemění“ o PR, o kterém se to
    /// zatím neví. Tatáž hranice, na které `Policy.fileStopDetail` u nenačteného diffu mlčí — a od
    /// #506/2 je to případ, který nastat umí, protože sloupec stojí i v tabech, kde se diff nenačítá.
    var files: Int?
    let expand: () -> Void

    var body: some View {
        Button(action: expand) {
            VStack(spacing: 9) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
                if let files {
                    Text(verbatim: "\(files)")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Palette.raised, in: .rect(cornerRadius: 4))
                    // Svislý popisek: **`fixedSize` a pak výška**, ne šířka. Otočený text má
                    // pořád vodorovný rámeček, takže omezením šířky se ořízne — a delší
                    // popisek pak leze přes odznak nad sebou.
                    Text(verbatim: Plural.word(
                        files,
                        one: "soubor",
                        few: "soubory",
                        many: "souborů"
                    ))
                        .font(.system(size: 10.5))
                        .tracking(0.6)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        // Otočení **nemění rozvržení** — rámeček zůstává vodorovný. Bez rámečku
                        // po otočení si tedy proužek vezme šířku nenatočeného textu a roztáhne
                        // se; proto se tady zadává **otočený otisk** (úzký a vysoký).
                        .frame(width: 13, height: 62)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .frame(width: Self.width, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Palette.chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.lineSoft).frame(width: 1) }
        .help(Policy.shortcutHelp("Rozložit itinerář", .itinerary))
        .accessibilityLabel("Rozložit itinerář")
    }

    /// Šířka složeného proužku — **z `Policy`**, ze stejného důvodu jako u rozloženého sloupce.
    static let width = Policy.treeColumnWidth(expanded: false)
}
