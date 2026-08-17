import SwiftUI

/// Svislý rail vlevo (#180) — navigace v aplikaci, ne v pull requestu.
///
/// Nahradil toolbar bočního panelu. Rozdíl je v tom, na co se ptá: toolbar nabízel akce nad
/// seznamem (obnovit, filtrovat), rail přepíná **co je v okně vidět**. Akce zůstaly nad obsahem,
/// kterého se týkají.
///
/// Šířka je 52 bodů a je to celé místo, které si bere: ikony se popiskem by z něj udělaly druhý
/// sloupec vedle seznamu, a ten už jednou v okně je.
///
/// **Pod oddělovačem stojí volba, ne obrazovka** (#278): přepínač vzhledu okna. Návrh ho tam má
/// (půlkolečko za `.sep`), a je to jediná položka railu, která nic neotevírá — proto **není**
/// případem `RailSection`. Kdyby byla, šlo by na vzhled „přepnout jako na obrazovku“, nabídla by
/// se v ⌘K mezi sekcemi a v okně by zbyla prázdná plocha; je na to test.
///
/// Klikem **cykluje** a ikona se s režimem mění (slunce / měsíc / kolečko s „A“); od #299 to tak
/// kreslí i návrh. Viz `AppearanceMode.railSymbol` a specifikace.
struct SidebarRail: View {
    @Binding var section: RailSection
    /// Kolik PR čeká ve frontě. `nil` = ještě se nenačetlo; nula se **nekreslí**, protože
    /// odznak s nulou tvrdí, že je co dělat.
    var queueCount: Int?
    /// Kolik vlastních PR **čeká na tah** (#331) — ne kolik jich je otevřených. Šest PR, ze
    /// kterých pět čeká na CI, není šest věcí k práci; čísla se v tom rail a karta na dashboardu
    /// rozcházejí schválně.
    var mineCount: Int?
    /// Kolik PR má rozdělané review.
    var draftCount: Int?
    /// Vybraný vzhled okna (#278). Čte se z konfigurace, takže rail **nedrží vlastní kopii** —
    /// jinak by v okně byla druhá pravda o tom, jaký režim platí.
    var appearance: AppearanceMode = .system
    /// Přepnutí vzhledu. Zapisuje do konfigurace a odtud to jde tou jedinou cestou do aplikace,
    /// takže rail sám nic nepřebarvuje.
    var setAppearance: (AppearanceMode) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(RailSection.allCases) { item(for: $0) }
            // Oddělovač z návrhu (`.rail .sep`): 20 × 1 bod, 6 bodů nad i pod — s mezerou
            // `VStack`u tedy 10, jak to má návrh (`gap: 4` + `margin: 6px 0`). Dělí **navigaci od
            // volby**: nad ním jsou obrazovky, pod ním věc, která žádnou neotevírá.
            separator
            appearanceItem
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(Palette.chrome)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }

    private var separator: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 20, height: 1)
            .padding(.vertical, 6)
    }

    /// Přepínač vzhledu okna (#278).
    ///
    /// **Tlačítko, které klikem cykluje** — ne nabídka ani popover. Stav nese **ikona** (slunce,
    /// měsíc, kolečko s „A“ pro automat), takže je vidět bez kliknutí; to je celý důvod, proč se
    /// ikona s režimem mění, i když jich návrh kreslí jednu.
    ///
    /// Cyklící tlačítko má jednu slabinu: z ikony je vidět, **kde jsem**, ne **kam se dostanu**.
    /// Nese to proto nápověda (`Vzhled: tmavý · kliknutím podle systému`) a pro VoiceOver
    /// `accessibilityValue` se stavem plus `accessibilityHint` s tím, co klik udělá. Cyklící
    /// tlačítko bez toho je hádanka.
    ///
    /// Rám je tentýž jako u položek nad oddělovačem (34 × 30), aby rail nedržel dvě velikosti ikon.
    /// Zvýrazněný stav (`.ri.on` z návrhu) **nedostává**: to znamená „jsem na téhle obrazovce“,
    /// a vzhled žádnou neotevírá.
    private var appearanceItem: some View {
        Button { setAppearance(appearance.next) } label: {
            Image(systemName: appearance.railSymbol)
                .font(.system(size: 15))
                .frame(width: 34, height: 30)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(appearanceHelp)
        .accessibilityLabel("Vzhled okna")
        .accessibilityValue(appearance.displayName)
        .accessibilityHint("Kliknutím přepneš na \(appearance.next.displayName.lowercased())")
    }

    /// Nápověda nese **stav i to, kam klik povede** — z ikony je poznat jen to první.
    private var appearanceHelp: String {
        "Vzhled: \(appearance.displayName.lowercased()) · kliknutím \(appearance.next.displayName.lowercased())"
    }

    private func item(for item: RailSection) -> some View {
        let isActive = section == item
        return Button { section = item } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 15))
                .frame(width: 34, height: 30)
                .background(isActive ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .overlay(alignment: .topTrailing) { badge(count(of: item)) }
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    /// Odznak s počtem. **Nula se nekreslí** — prázdná fronta je dobrá zpráva, ne položka
    /// k vyřízení; a `nil` (nenačteno) se od nuly musí lišit, jinak by okno po startu tvrdilo
    /// „nic tu není“ nad daty, která ještě nedorazila.
    @ViewBuilder private func badge(_ count: Int?) -> some View {
        if let count, count > 0 {
            Text(verbatim: "\(count)")
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.tint, in: .capsule)
                .foregroundStyle(.white)
                .offset(x: 6, y: -2)
        }
    }

    private func count(of item: RailSection) -> Int? {
        switch item {
        // Dashboard odznak nemá: sám je souhrn, takže by číslo vedle ikony opakovalo to,
        // co je za ní vidět.
        case .overview: nil
        case .queue: queueCount
        case .mine: mineCount
        case .drafts: draftCount
        }
    }

}
