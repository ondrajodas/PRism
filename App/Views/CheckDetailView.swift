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
        case .loading(let bytes):
            // Věta se skládá v `Policy`, ne tady: je to rozhodnutí o tom, co se smí slíbit, když
            // velikost neznáme (#292). Sbalení checku stahování zruší, takže je to čekání, ze
            // kterého je cesta pryč.
            note(Policy.logDownloadNotice(bytes: bytes), systemImage: nil, spinner: true)
        case .loaded(_, let tail):
            tailView(tail)
        case .tooLarge(let reason):
            // Věta s **konkrétní velikostí** — a odkaz na GitHub vedle v akcích výš. Velikost je
            // z `Content-Length`, a když ji odpověď neřekla, ze stažených bajtů (#292); ukázat se
            // log nemá v obou případech stejně, takže věta zůstává jedna.
            note("\(reason) Celý je na GitHubu.", systemImage: "doc.text.magnifyingglass")
        case .failed(let reason):
            // **Ne prázdný log.** Selhané stažení se nesmí tvářit jako log, ve kterém nic není.
            note("Konec logu se nepodařilo stáhnout. \(reason)", systemImage: "exclamationmark.triangle")
        }
    }

    /// Sazba konce logu — velikost, prokládání a strop na výšku okýnka.
    ///
    /// Drží se pohromadě, protože **výška se z prvních dvou počítá** (#236): kdo si říká o velikost,
    /// musí ji měřit na tom, na čem kreslí.
    /// `nonisolated` schválně: výška se počítá i mimo hlavní vlákno (`LogTailTextView.height`) a
    /// testy nad ní jsou nonisolated. Jsou to čísla, ne stav.
    nonisolated static let logFontSize: CGFloat = 10.5
    nonisolated static let logLineSpacing: CGFloat = 2

    /// Strop na výšku okýnka: **445 bodů, tedy přesně 30 řádků** (`30 × 14 + 2 × 4 + 17`).
    ///
    /// **Zvednuto z 320 bodů (21 řádků) u #303**, na výslovné přání po proklikání — a kolik přesně,
    /// rozhodlo měření (`CheckLogRoomProbe`), ne odhad. Číslo padne na **celý řádek**, ne na půlku:
    /// hodnoty jsou `14N + 25`, takže se okýnko nezavírá uprostřed písmen.
    ///
    /// **Ze 441 na 445 u #347**, a je to oprava rezervy, ne nové rozhodnutí o výšce: rezerva na
    /// vodorovný scroller byla odměřená na `.small` scrolleru (13 bodů) místo na tom `.regular`, který
    /// se kreslí (17), takže na text zbývalo `(441 − 8 − 17) / 14` = **29,71 řádku** — strop sliboval
    /// 30 řádků a ukázal 29. Rozhodnutí „30 řádků“ z #303 zůstává v platnosti, mění se jen číslo, na
    /// kterém ho dostaneme. Ta rezerva a tenhle strop jsou **pár** (viz
    /// `LogTailTextView.horizontalScrollerHeight`) — jeden se bez druhého posunout nedá.
    ///
    /// Cena je **změřená znovu**, ne odhadnutá (`CheckLogRoomProbe`, řádek seznamu 28 bodů): každé
    /// „zbylo“ v tabulce níž se zmenší o 4 body. Na okně, na kterém se aplikace používá, je to
    /// 172 → 168 bodů, tedy **pořád 6 řádků seznamu** — rozhodující řádek tabulky tím nehne. Zaplatí
    /// to okno 810, kde ze 30 bodů zbyde 26, tedy z jednoho řádku žádný.
    ///
    /// **Co se měřilo: kolik zbude na seznam checků.** Původní 320 má zapsaný důvod — 300 řádků
    /// nasázených naplno odtlačilo zbytek seznamu mimo obrazovku, tedy zrovna to, kvůli čemu se
    /// detail checku stěhoval z `Přehledu` do vlastního tabu (#215). Rozbalený spadlý check stojí
    /// v seznamu první, takže je to nejhorší případ; nad okýnkem je vždycky 173 bodů (hlavička
    /// karty, řádek checku, anotace, akce a hlavička „nevešlo se“):
    ///
    /// | Okno | Viewport tabu | Zbylo při 320 | Zbylo při 441 |
    /// |---|---|---|---|
    /// | 952 (okno na tomhle stroji) | 786 | 293 b = 10 řádků | **172 b = 6 řádků** |
    /// | 810 | 644 | 151 b = 5 řádků | 30 b = 1 řádek |
    /// | 700 (`defaultSize`) | 534 | 41 b = 1 řádek | −80 b |
    /// | 400 (podlaha `RootView`) | 234 | −259 b | −380 b |
    ///
    /// **Cena je zapsaná**: v okně od ~810 bodů výš seznam pod okýnkem pořád je, ve výchozím 700 se
    /// odscrolluje (a při 320 tam byl jeden řádek). Není to ale ztráta logu — z okýnka je i tam
    /// vidět 24 řádků bez dotčení vnějšího scrollu, tedy pořád víc než dnešních 21.
    ///
    /// **Zamítnuto 525 bodů (36 řádků)**: na skutečném okně zbydou 3 řádky seznamu a v okně 810 už
    /// nezbude nic — z okýnka by byl celý tab. A **zamítnuto 357 bodů (24 řádků)**, tedy největší
    /// hodnota, u které se okýnko celé vejde i do výchozího okna: +3 řádky nejsou změna, o kterou
    /// se prosilo.
    nonisolated static let logMaxHeight: CGFloat = 445

    /// Konec logu (`.logtail`): mono, bez zalamování, s vodorovným scrollem.
    ///
    /// **Kreslí to `NSTextView`, ne SwiftUI `Text`** (#292) — a je to to jediné, co dovoluje ukázat
    /// tisíce řádků: `Text` se `.fixedSize()` roste kvadraticky (2 000 řádků 6 s, 10 000 řádků dvě
    /// a půl minuty), kdežto TextKit sází **líně po viewportu** (2 000 řádků 1,12 ms). Čísla i rozbor
    /// jsou u `LogTailTextView`.
    ///
    /// Odtud plyne i to, co odsud **zmizelo**: dvouosý `ScrollView`, `fixedSize()` a dolní mez šířky
    /// z `availableWidth` (#220). Zarovnání doleva ani scrollování už není co vyjednávat — obojí
    /// dělá `NSScrollView` sám, a proto je tenhle kus kódu kratší než dřív.
    private func tailView(_ tail: LogTail) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // **Tiše zkrácený log tvrdí, že job začal uprostřed** — proto hlavička s počtem.
            if let notice = Policy.logTailNotice(tail) {
                Text(verbatim: notice)
                    .font(.system(size: Self.logFontSize, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
            }
            // **Výška je zastropovaná a scrolluje se uvnitř.** Šest tisíc řádků nasazených naplno by
            // odtlačily zbytek seznamu checků mimo obrazovku — a to je zrovna to, kvůli čemu se
            // detail stěhoval z `Přehledu` (#215). Návrh tuhle mez nekreslí, protože v něm je log
            // ukázaný na osmi řádcích; s `Policy.logTailLines` řádky je potřeba. Kolik ten strop je
            // a co po něm zbývá vidět ze seznamu, je u `logMaxHeight` — i s měřením.
            //
            // Krátký log si přitom vezme jen tolik, kolik má řádků, takže pod třířádkovým logem
            // nezbyde prázdné okýnko.
            LogTailTextView(
                text: tail.text,
                fontSize: Self.logFontSize,
                lineSpacing: Self.logLineSpacing,
                color: Palette.ink2
            )
            .frame(height: LogTailTextView.height(
                forLines: tail.lineCount,
                fontSize: Self.logFontSize,
                lineSpacing: Self.logLineSpacing,
                limit: Self.logMaxHeight
            ))
        }
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .padding(.top, 9)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised)
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
