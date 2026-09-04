import SwiftUI

/// Levý sloupec záložky PR: **itinerář review** místo stromu souborů (#506).
///
/// Okno má osm záložek a diff o padesáti souborech, ale žádné pořadí — co číst první, kde jsem
/// skončil a co zbývá, si člověk do #506 držel v hlavě. Reviewer má dráhu s fázemi (tab `Průběh`);
/// člověk, který review dělá, neměl nic.
///
/// Sloupec je proto **dráha se zastávkami** v pevném pořadí *Od minule → Popis a záměr → Soubory
/// podle rizika → Kontroly → Verdikt*, u každé stav (✓ hotovo / ● aktuální / ○ zbývá) a údaj
/// vpravo. **Které zastávky v seznamu jsou, skládá `Policy` z dat**, ne šablona — viz
/// `Policy.itinerary`.
///
/// **Strom podle cesty tady není a je to změna proti #197.** Společné prefixy zabíraly v úzkém
/// sloupci většinu šířky (to byl důvod stromu) — jenže cesta se od #219 píše v **hlavičce
/// souboru** v diffu, takže ve sloupci nechybí, a pořadí podle rizika odpovídá na otázku, na
/// kterou hloubka složek odpovědět neumí: čím začít. Strom podle cesty se otevírá zpátky jako
/// #197.
///
/// **Nic se tu nezaškrtává rukou kromě souboru** (`Prošlo`, #500). Itinerář, který si člověk
/// odškrtává sám, je druhý seznam úkolů — hotovo se pozná z dat.
struct ReviewItineraryView: View {
    /// Položky seznamu souborů — `Policy.filesByRisk`. Konfigurace a locky jsou složené do jedné.
    let items: [ItineraryFileItem]
    /// Zastávky — `Policy.itinerary`, složené volajícím.
    ///
    /// **Nepovinné to od #506/2 není, a je to změna proti prvnímu kolu**: sloupec tehdy stál
    /// uvnitř `Změněných souborů`, takže ho dostal i diff commitu (#317) a rozsah od minule
    /// (#284) — a tam zastávky nebyly. Od druhého kola sloupec hostí detail PR a mluví vždycky
    /// o celém pull requestu, takže „sloupec bez zastávek“ nemá kdo vyrobit; nepovinná hodnota
    /// by byla větev, kterou nikdo neprojde.
    let itinerary: ItineraryActions
    /// Které soubory nesou nález (#197) — puntík za jménem.
    var markers: [String: FileMarker] = [:]
    /// Stav značky `Prošlo` (#500). Prázdné = nic prošlého, tedy ani ✓, ani ↻.
    var readStates: [String: FileReviewState] = [:]
    let jump: (FileDiff) -> Void

    /// Je skládaná položka `4 konfigurace a locky` rozbalená?
    ///
    /// `@State` sloupce, ne store: je to odchylka pohledu do zavření záložky a nic na ní nevisí —
    /// na rozdíl od sbalení souboru v diffu, které se odvozuje ze značky (#500).
    @State private var bundleExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(itinerary.stops) { stop in
                    stopRow(stop, in: itinerary)
                    // Soubory visí **pod svou zastávkou**, ne pod celým seznamem: zastávka
                    // `Soubory podle rizika` je jediná, jejíž práce se dělí na položky, a
                    // počítadlo v hlavičce (`4 z 11`) je počítá.
                    if stop.kind == .files { fileList }
                }
            }
            .padding(.vertical, 6)
        }
        // **Rozměr se měří, nevyjednává** (#361): sloupec stojí ve `VStack`u, takže by mu ten
        // `VStack` posílal průzkumné dotazy na pružnost skrz na celý seznam.
        .fillingSlot()
    }

    // MARK: - Zastávky

    private func stopRow(_ stop: ItineraryStop, in itinerary: ItineraryActions) -> some View {
        Button { itinerary.select(stop) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                stateGlyph(stop.state)
                Text(verbatim: stop.title)
                    .font(.system(size: 11.5, weight: stop.state == .current ? .semibold : .regular))
                    .foregroundStyle(stop.state == .done ? AnyShapeStyle(Palette.ink3) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let detail = stop.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                        // Údaj vpravo ustupuje nadpisu: nadpis říká, **co** se dělá, údaj jen
                        // kolik toho je. Bez tohohle by se v úzkém sloupci ořezával nadpis.
                        .layoutPriority(-1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(stop.state == .current ? Palette.accentWeak : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Policy.itineraryStopHelp(stop))
    }

    /// ✓ hotovo / ● aktuální / ○ zbývá. **Pevná šířka**, ať se nadpisy srovnají do kolony.
    @ViewBuilder private func stateGlyph(_ state: ItineraryStop.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.ok)
                .frame(width: 11)
        case .current:
            Circle()
                .fill(Palette.accent)
                .frame(width: 6, height: 6)
                .frame(width: 11)
        case .todo:
            Circle()
                .strokeBorder(Palette.ink3, lineWidth: 1)
                .frame(width: 6, height: 6)
                .frame(width: 11)
        }
    }

    // MARK: - Soubory podle rizika

    /// Seznam souborů — skupiny s nadpisem, pod nimi řádky.
    ///
    /// **Pevný `VStack`, ne líný seznam** (#469): laznost je vlastnost layoutu, ne délky seznamu,
    /// a padesát řádků o jednom `Text`u je proti bloku kódu nic. Odsazení je jedna úroveň, ne
    /// hloubka složek — sloupec neřadí podle cesty.
    @ViewBuilder private var fileList: some View {
        ForEach(Policy.itineraryGroups(items)) { group in
            Text(verbatim: group.risk.groupTitle.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .padding(.leading, Self.fileIndent)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(group.items) { item in
                itemRow(item, indent: Self.fileIndent)
            }
        }
    }

    @ViewBuilder private func itemRow(_ item: ItineraryFileItem, indent: Double) -> some View {
        switch item {
        case .file(let file, _):
            // **Riziko se do řádku nepředává**, i když ho položka nese: řádek kreslí ikonu podle
            // **druhu změny** a puntík podle nálezu, kdežto riziko je vidět z **nadpisu skupiny**
            // nad ním. Parametr, který nikdo nečte, svádí spolehnout se na něj.
            fileRow(file, indent: indent)
        case .bundle(let files):
            bundleRow(files, indent: indent)
            if bundleExpanded {
                ForEach(files) { file in
                    fileRow(file, indent: indent + Self.fileIndent)
                }
            }
        }
    }

    private func fileRow(_ file: FileDiff, indent: Double) -> some View {
        Button { jump(file) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(of: file))
                    .font(.caption)
                    // Ikona nese **druh změny barvou**, ne jen tvarem (#501) — zelená přidává,
                    // červená maže, modrá přejmenovává. Tvar sám se u `plus.square`
                    // a `minus.square` čte až po zaostření, kdežto barva se vezme periferně.
                    .foregroundStyle(tint(of: file) ?? AnyShapeStyle(.secondary))
                    .frame(width: 14)
                Text(verbatim: file.displayPath.split(separator: "/").last.map(String.init) ?? file.displayPath)
                    .font(.caption)
                    // Prošlý soubor je tlumený (`.tnode.rv-done .nm` v návrhu) — oko po něm
                    // klouže dál, ale jméno zůstává čitelné. `changed` tlumený **není**: je to
                    // práce, která se vrátila.
                    .foregroundStyle(nameTint(of: file))
                    .lineLimit(1)
                    // **Zezadu**: u jména souboru nese význam začátek — `SecretClient.php`
                    // a `SecretClientTest.php` se poznají jen podle něj.
                    .truncationMode(.tail)
                if let marker = markers[file.displayPath] {
                    Circle()
                        .fill(marker == .blocking ? Palette.crit : Palette.find)
                        .frame(width: 6, height: 6)
                        .help(marker == .blocking ? "Je tu blokující nález" : "Jsou tu nálezy")
                }
                readGlyph(of: file)
                Spacer(minLength: 6)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 13)
            .padding(.leading, indent)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(file.displayPath)
    }

    /// Skládaná položka `4 konfigurace a locky` — jeden řádek, který se rozbalí.
    private func bundleRow(_ files: [FileDiff], indent: Double) -> some View {
        // **Jedno spočítání, ne dvě**: podmínka i text se ptají na totéž, a dvě čtení mapy jsou
        // dvě odpovědi na jednu otázku.
        let read = bundleReadCount(files)
        return Button { bundleExpanded.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: bundleExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                Text(verbatim: Policy.configurationBundleLabel(count: files.count))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                if read > 0 {
                    Text(verbatim: "\(read)/\(files.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.ok)
                }
                Spacer(minLength: 6)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 13)
            .padding(.leading, indent)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Konfigurace a locky — generuje je nástroj, takže se čtou na konci")
    }

    private func bundleReadCount(_ files: [FileDiff]) -> Int {
        files.count { (readStates[$0.displayPath] ?? .unread).isRead }
    }

    /// Značka `Prošlo` (#500) — ✓ v `--ok` u prošlého, ↻ v `--stale` u změněného od prošlého.
    ///
    /// **Stojí vedle puntíku nálezu, ne místo něj**: jsou to odpovědi na dvě různé otázky („je tu
    /// co spravit“ proti „četl jsem to“) a schovat jednu za druhou by znamenalo, že se počítadlo
    /// v hlavičce rozejde s tím, co je v seznamu vidět.
    @ViewBuilder private func readGlyph(of file: FileDiff) -> some View {
        switch readStates[file.displayPath] ?? .unread {
        case .unread:
            EmptyView()
        case .read:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.ok)
                .help("Prošlo")
        case .changed:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.stale)
                .help("Změněno od prošlého")
        }
    }

    private func nameTint(of file: FileDiff) -> AnyShapeStyle {
        (readStates[file.displayPath] ?? .unread).isRead
            ? AnyShapeStyle(Palette.ink3)
            : AnyShapeStyle(.primary)
    }

    private func tint(of file: FileDiff) -> AnyShapeStyle? {
        switch file.change {
        case .added: AnyShapeStyle(Palette.ok)
        case .deleted: AnyShapeStyle(Palette.crit)
        case .renamed: AnyShapeStyle(Color.blue)
        case .modified: nil
        }
    }

    private func symbol(of file: FileDiff) -> String {
        if file.isBinary { return "doc.badge.gearshape" }
        switch file.change {
        case .added: return "plus.square"
        case .deleted: return "minus.square"
        case .renamed: return "arrow.triangle.turn.up.right.diamond"
        case .modified: return "doc.text"
        }
    }

    /// O kolik jsou soubory odsazené pod zastávkou. **Jedna úroveň, ne hloubka složek** —
    /// a málo, protože v úzkém sloupci každý bod ukusuje z jména.
    private static let fileIndent = 12.0
}
