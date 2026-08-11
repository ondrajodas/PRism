import SwiftUI

/// Detail rozbaleného checku (#214) — anotace a konec logu.
///
/// **Anotace z CI není nález z review** a nesmí s ním splynout ani barvou, ani tvarem: nález má
/// revieweera, dá se odmítnout a počítá se; anotace je cizí fakt, se kterým se nedá dělat nic než
/// opravit kód. Proto plochý řádek se štítkem (návrh, `.ann`), ne bublina s obrysem a levým
/// pruhem jako `FindingBubbleView`.
struct CheckDetailView: View {
    let detail: CheckDetailState
    /// Odkaz na check na GitHubu — `Otevřít celý log na GitHubu`. `nil` = odkaz nemáme.
    let link: URL?
    /// Skočit na `soubor:řádek` z anotace. `nil` = skákat není kam (diff se nenačetl).
    var jump: ((String, Int?) -> Void)?
    /// Ukázat celý log v sheetu. Dostane celý text, ne ořezaný.
    var showFullLog: ((String) -> Void)?
    let collapse: () -> Void

    /// Odsazení obsahu detailu — sedí pod jménem checku, ne pod jeho ikonou (návrh: `padding-left:
    /// 34px` u `.ann`, `.chkacts` i `.logtail`).
    private let indent: CGFloat = 34

    /// Šířka, kterou tab dostal (#220). Konec logu ji potřebuje, aby se dal **zarovnat doleva**:
    /// `ScrollView` obsah užší než viewport vystředí a uvnitř dvouosého scrollu se šířka
    /// vyjednat nedá (obsah dostane neomezenou nabídku). `nil` = nikdo neměřil (náhledy, testy),
    /// pak se nechá být.
    @Environment(\.availableWidth) private var availableWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            annotations
            actions
            log
        }
    }

    // MARK: - Anotace

    @ViewBuilder private var annotations: some View {
        switch detail.annotations {
        case .loading:
            note("Načítám anotace…", systemImage: nil, spinner: true)
        case .loaded(let annotations) where annotations.isEmpty:
            // **Prázdno je běžný stav, ne porucha**: anotace emituje jen workflow, které si o to
            // řekne (problem matcher, reporter). U běžného `phpunit`/`phpstan` nejsou — a přesně
            // proto je log ta hlavní cesta.
            note("Workflow nenahlásilo žádné anotace — příčina bude v logu.", systemImage: nil)
        case .loaded(let annotations):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(annotations.items) { annotation in
                    row(annotation)
                    if annotation.id != annotations.items.last?.id {
                        Rectangle().fill(Palette.lineSoft).frame(height: 1)
                    }
                }
                shortfall(annotations)
            }
            .background(Palette.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        case .failed(let reason):
            // **Ne prázdno.** „Anotace se nepodařilo načíst“ se nesmí čít jako „žádné nejsou“.
            note("Anotace se nepodařilo načíst. \(reason)", systemImage: "exclamationmark.triangle")
        }
    }

    private func row(_ annotation: CheckAnnotation) -> some View {
        HStack(alignment: .top, spacing: 9) {
            level(annotation.level)
            Text(verbatim: annotation.message)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            location(annotation)
        }
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
    }

    /// Štítek `error` / `warning` / `notice` (`.ann .lvl`).
    private func level(_ level: CheckAnnotation.Level) -> some View {
        Text(verbatim: level.label.uppercased())
            .font(.system(size: 9.5, design: .monospaced))
            .kerning(0.6)
            .foregroundStyle(color(of: level))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color(of: level).opacity(0.14), in: .rect(cornerRadius: 4))
            .padding(.top, 1)
    }

    /// **Jiná škála než u nálezů** není potřeba — je to tatáž paleta, ale tvar (plochý štítek,
    /// ne bublina s pruhem) drží rozdíl, o který jde.
    private func color(of level: CheckAnnotation.Level) -> Color {
        switch level {
        case .failure: Palette.crit
        case .warning: Palette.find
        case .notice: Palette.ink3
        }
    }

    /// `soubor:řádek ↗` — kliknutí skočí do diffu.
    ///
    /// Tlačítko jen tehdy, když **je kam skočit**: anotace umí ukazovat mimo diff (typicky
    /// `.github/workflows/…`, u změřeného jobu `.github:5015`), a odkaz, který nic neudělá, je
    /// horší než text.
    @ViewBuilder private func location(_ annotation: CheckAnnotation) -> some View {
        let label = annotation.line.map { "\(annotation.path):\($0)" } ?? annotation.path
        if let jump, annotation.line != nil {
            Button {
                jump(annotation.path, annotation.line)
            } label: {
                Text(verbatim: "\(label) ↗")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
            .help("Skočit na místo v diffu")
        } else {
            Text(verbatim: label)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
        }
    }

    /// Kolik anotací se nevešlo. **Dvě různá „chybí“**, protože se o nich ví různě moc — přesný
    /// počet u stažených a „možná další“ u plné stránky (bez počtu, ten neznáme).
    @ViewBuilder private func shortfall(_ annotations: CheckAnnotations) -> some View {
        if annotations.missing > 0 || annotations.mayHaveMore {
            let parts = [
                annotations.missing > 0
                    ? Plural.czech(annotations.missing, one: "další anotace", few: "další anotace", many: "dalších anotací")
                    : nil,
                annotations.mayHaveMore ? "a možná i víc, než GitHub vydal na jednu stránku" : nil,
            ].compactMap { $0 }
            Text(verbatim: "Nevešlo se: \(parts.joined(separator: " "))")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .padding(.leading, indent)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Akce

    /// Akce nad logem (`.chkacts`). Stojí **nad** logem, jak je má návrh — jsou to jeho ovládání.
    private var actions: some View {
        HStack(spacing: 7) {
            mini("Skrýt konec logu", action: collapse)
            if case .loaded(let full, _) = detail.log, let showFullLog {
                mini("Ukázat celý log") { showFullLog(full) }
            }
            if let link {
                Link(destination: link) {
                    Text(verbatim: "Otevřít celý log na GitHubu ↗")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Palette.surface, in: .rect(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    private func mini(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Palette.surface, in: .rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Konec logu

    @ViewBuilder private var log: some View {
        switch detail.log {
        case .loading:
            note("Stahuji konec logu…", systemImage: nil, spinner: true)
        case .loaded(_, let tail):
            tailView(tail)
        case .tooLarge(let reason):
            // Věta s **konkrétní velikostí** z `Content-Length` — a odkaz na GitHub vedle
            // v akcích výš. Nestahovalo se vůbec.
            note("\(reason) Celý je na GitHubu.", systemImage: "doc.text.magnifyingglass")
        case .failed(let reason):
            // **Ne prázdný log.** Selhané stažení se nesmí tvářit jako log, ve kterém nic není.
            note("Konec logu se nepodařilo stáhnout. \(reason)", systemImage: "exclamationmark.triangle")
        }
    }

    /// Konec logu (`.logtail`): mono, bez zalamování, s vodorovným scrollem.
    ///
    /// **Jeden `Text` na celý ocas**, ne `Text` na řádek: tři stovky řádků jako tři stovky views
    /// je tatáž chyba, jakou #252 vyndal z gutteru diffu. Jeden text si SwiftUI nasází sám.
    private func tailView(_ tail: LogTail) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // **Tiše zkrácený log tvrdí, že job začal uprostřed** — proto hlavička s počtem.
            if let notice = Policy.logTailNotice(tail) {
                Text(verbatim: notice)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
            }
            // **Výška je omezená a scrolluje se uvnitř.** Tři stovky řádků nasazených naplno
            // odtlačí zbytek seznamu checků mimo obrazovku — a to je zrovna to, kvůli čemu se
            // detail stěhoval z `Přehledu` (#215). Návrh tuhle mez nekreslí, protože v něm je log
            // ukázaný na osmi řádcích; s `Policy.logTailLines` řádky je potřeba.
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                // **Doleva, ne na střed.** `ScrollView` obsah užší než viewport vystředí, takže
                // krátké řádky logu skončily v polovině plochy — chyceno offscreen renderem.
                // `frame(maxWidth:alignment:)` to nespraví: `fixedSize()` velikost zamkne, takže
                // rámeček nad ním nemá co roztáhnout. Zabere až `Spacer` **vedle** textu.
                Text(verbatim: tail.text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize()
                    // Šířka **spočítaná, ne vyjednaná** (#220): obsah musí být aspoň tak široký
                    // jako viewport, jinak ho `ScrollView` vystředí. `Spacer` to nespraví —
                    // uvnitř dvouosého scrollu dostane obsah neomezenou nabídku, takže se
                    // `Spacer` stáhne na nulu; chyceno offscreen renderem.
                    .frame(minWidth: contentWidth, alignment: .leading)
            }
            .frame(maxHeight: 320)
        }
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .padding(.top, 9)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised)
    }

    /// Kolik místa má obsah logu k dispozici — šířka tabu bez odsazení a bez rámečku karty.
    /// `0` znamená „nevím“, tedy žádná dolní mez: text si vezme svou vlastní šířku.
    private var contentWidth: CGFloat {
        guard let availableWidth else { return 0 }
        // 16 na každou stranu je padding tabu, 1 obrys karty, `indent` + 12 je odsazení detailu.
        return max(0, availableWidth - 2 * 16 - 2 - indent - 12)
    }

    private func note(_ text: String, systemImage: String?, spinner: Bool = false) -> some View {
        HStack(spacing: 6) {
            if spinner { ProgressView().controlSize(.small) }
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(Palette.ink3)
            }
            Text(verbatim: text)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }
}
