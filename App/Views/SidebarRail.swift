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
///
/// **Aktivní sekci značí pruh na hraně, ne jen barva ikony** (#526, návrh sekce 50). Odznak jde
/// od #526 do **rohu** ikony, tedy ven z jejího rámu — ikona pod ním zůstane celá a odznak se
/// kreslí i na aktivní položce. Kdyby identita aktivní sekce dál stála jen na fialové ikoně,
/// nebyla by pod dvoumístným počtem vidět.
struct SidebarRail: View {
    /// Šířka railu (návrh, `.body-grid`): 52 bodů, a je to celé místo, které si bere.
    ///
    /// Je to konstanta, ne dvě napsaná čísla, protože si ji od #526 bere **i řádek položky**: pruh
    /// aktivní sekce leží na **hraně railu**, ne u ikony, takže se má kam pověsit jedině tehdy,
    /// když řádek rail vyplňuje. Dvě čísla by se rozešla a poznalo by se to až v bitmapě.
    static let width: CGFloat = 52

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
    /// Kolik položek dění je **nepřečtených** (#414) — ne kolik jich v záznamu je. `nil` znamená
    /// „nekreslit“, a od #526 do toho padá jedině **není co**: aktivní `Dění` odznak dostane taky,
    /// protože ho od #526 nese roh ikony a aktivní sekci značí pruh na hraně railu.
    /// Rozhoduje `Policy.activityBadge(unread:)`, ne tohle view.
    var activityCount: Int?
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
        .frame(width: Self.width)
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
        .help(Policy.shortcutHelp(item.title, .openSection(item)))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        // **Řádek si bere celou šířku railu, tlačítko zůstává 34 bodů** (#526). Pruh aktivní
        // sekce visí na hraně railu, tedy 9 bodů nalevo od rámu ikony — a `overlay` mimo plochu
        // rodiče by ho položil na místo, které rodič nemá. Rám tlačítka se přitom rozšířit
        // **nesmí**: klikací plocha by se nafoukla na celou šířku railu a klik do prázdna vedle
        // ikony by přepínal sekci. `frame` nasazený **za** `buttonStyle` tlačítko jen vystředí.
        .frame(width: Self.width)
        .overlay(alignment: .leading) { activeStripe(isActive) }
    }

    /// Pruh aktivní sekce na levé hraně railu (#526, návrh sekce 50).
    ///
    /// **Tentýž prvek, kterým okno značí stav na hraně řádku fronty** (`PullRequestRow`), jen
    /// svisle: barva na kraji se přečte periferně a nezávisí na tom, co je na ikoně. Do #526
    /// nesla identitu aktivní sekce jedině ikona — fialová na fialovém washi —, jenže právě ta je
    /// pod odznakem, takže se na ni s odznakem v rohu nedá spolehnout.
    ///
    /// Rozměry jsou z návrhu doslova (`.rail .ri.on::before`): **2 × 18 bodů**, poloměr 1, akcent.
    /// Osmnáctka je `top: 6` a `bottom: 6` v rámu vysokém 30, takže se pruh počítá **z výšky
    /// řádku**, ne z výšky ikony — kdyby se řádek změnil, pruh se s ním má hýbat.
    ///
    /// Barva je `.tint`, ne `Palette.accent`: tutéž barvu bere podklad i glyf aktivní položky
    /// o dva řádky výš, a dvě jména pro jednu barvu jsou dvě místa, na kterých se dá rozejít.
    @ViewBuilder private func activeStripe(_ isActive: Bool) -> some View {
        if isActive {
            RoundedRectangle(cornerRadius: 1)
                .fill(.tint)
                .frame(width: 2, height: 18)
        }
    }

    /// Odznak s počtem. **Nula se nekreslí** — prázdná fronta je dobrá zpráva, ne položka
    /// k vyřízení; a `nil` (nenačteno) se od nuly musí lišit, jinak by okno po startu tvrdilo
    /// „nic tu není“ nad daty, která ještě nedorazila.
    ///
    /// **Červený** (#366, návrh `.rail .ri .badge`). Do #366 to byl fialový akcent; akcent v tomhle
    /// okně znamená „tady jsi“ (`.ri.on` je z něj celý), takže odznak v téže barvě netvrdil nic —
    /// červená (`--crit`) je „je co dělat“, a to je přesně to, co počet ve frontě je.
    ///
    /// **A od #526 v rohu, tedy ven z rámu ikony** (`top: −5, right: −7` v návrhu, sekce 50) — což
    /// je oprava druhé poloviny #366. Uvnitř rámu 34 × 30 nemá odznak 24 × 18 kam sednout: ať je
    /// posazený kamkoli, zakryje ikonu, a v běžícím okně z ní pod `5`, `3` a `30` byla vidět jen
    /// spodní hrana. Sedmi body vpravo zbývá k pravé hraně railu ještě 2 body, takže se pořád
    /// kreslí uvnitř těch 52 — a **nic ho neořezává**: rail není `ScrollView` ani `clipShape`
    /// (#483), takže `overlay` mimo plochu rodiče přežije. Je to na to test v bitmapě, ne úvaha.
    ///
    /// Rozměry jsou z CSS doslova: obsah **14 × 14**, odsazení 3 na stranu, obtah 2 barvou railu
    /// (`--panel-2`), poloměr 7 zvenčí a 5 zvnitřku (CSS obtah poloměr zmenšuje). Vyjde z toho
    /// 24 × 18 na jednu i dvě cifry — **změřeno na vyrenderované sekci 02**, ne odhadnuto z popisu:
    /// `min-width` a `height` v návrhu jsou **obsah**, protože dokument `box-sizing` nikde
    /// nepřepisuje, takže odsazení a obtah se k nim přičítají.
    ///
    /// Výška je `minHeight`, ne `frame(height:)` — u mono 9 bold je řádek 11 bodů, takže se ta
    /// čtrnáctka chová jako podlaha a nasazený rámec by číslo uřízl, kdyby se písmo systému
    /// změnilo (#325). Text je v barvě **plochy okna** (`--panel`), ne bíle: bílá by na světlé
    /// červené měla kontrast 3,35, kdežto takhle je to 5,36 ve světlém a 5,50 v tmavém režimu.
    @ViewBuilder private func badge(_ count: Int?) -> some View {
        if let count, count > 0 {
            Text(verbatim: "\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.surface)
                .frame(minWidth: 14, minHeight: 14)
                .padding(.horizontal, 3)
                .background(Palette.crit, in: .rect(cornerRadius: 5))
                .padding(2)
                .background(Palette.chrome, in: .rect(cornerRadius: 7))
                // Roh, ne rám (#526). Do #526 tu stálo `offset(y: 1)`, tedy `top: 1, right: 0`
                // z návrhu před opravou. `offset` layout nemění, takže se řádek položky nenafoukne
                // a svislice ikon zůstane, kde byla.
                .offset(x: 7, y: -5)
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
        case .activity: activityCount
        }
    }

}
