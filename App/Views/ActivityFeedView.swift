import SwiftUI

/// Sekce railu `Dění` (#414) — co se na pull requestech stalo, když jsem se nekoukal.
///
/// **Sekce, ne blok na dashboardu ani popover.** Dashboard odpovídá na „co hoří teď“ a kreslí
/// nejvýš pět řádků na blok (#371), takže by z dění byla ukázka, ne místo, kde se dá zůstat;
/// popover se zavře prvním kliknutím a nedá se v něm rolovat.
///
/// Rozměry a barvy jsou z návrhu (sekce 27) doslova; kdo je mění, mění návrh.
struct ActivityFeedView: View {
    var days: [ActivityFeedDay] = []
    /// Prázdný stav. `nil` = něco v seznamu je.
    var empty: ActivityEmptyState?
    /// Věta pod nadpisem — skládá ji `Policy.activityHeaderSentence(lastVisit:hasEvents:now:calendar:)`.
    var subtitle = ""
    /// Značka poslední návštěvy — čas v pruhu `Tady jsem skončil`. `nil` = pruh se nekreslí.
    var lastVisit: Date?
    /// Kdy se seznam PR naposledy načetl. `nil` = ještě nikdy.
    var lastSuccess: Date?
    /// **Jedny hodiny na celou obrazovku.** Proti nim se počítá všechno, co na „teď“ stojí — název
    /// dne v nadpisu bloku, věta pod titulkem, popisek pruhu i čas u řádku. Kdyby si je každý kus
    /// bral sám (`Date()`), dostala by se do jedné obrazovky dvě různá „teď“: nad hlavičkou `Dnes`
    /// by v řádku stálo relativní stáří proti jinému okamžiku a nad `FakeTimeSource`m by se sonda
    /// rozešla s tím, co jí store nastavil. Nález Copilota na #418.
    var now = Date()
    /// Klik na řádek. **Jedna cesta** — otevřít záložku PR a v ní cílový tab (#409); `.gitHub`
    /// jediné vede z aplikace ven.
    var open: (ActivityEvent) -> Void = { _ in }
    /// Otevře okno nastavení — jediný odkaz v hlavičce vede tam, kde se hlášení vypíná
    /// (návrh, poznámka 94).
    var openSettings: () -> Void = {}
    /// Otevře Nastavení systému u zakázaného oprávnění. Aplikace tam sama nedosáhne, takže je to
    /// jediný další krok, který se dá nabídnout.
    var openSystemSettings: () -> Void = {}

    var body: some View {
        let _ = RenderDiagnostics.pass(Self.self)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                head
                if let empty {
                    ActivityFeedEmptyView(
                        state: empty,
                        openSettings: openSettings,
                        openSystemSettings: openSystemSettings
                    )
                } else {
                    // **Líný jen po dnech.** Blok je ohraničená karta, takže potřebuje jeden
                    // kontejner — a řádků v něm je nejvýš tolik, kolik je strop celého záznamu
                    // (200, `Policy.activityLimit`), takže je nejhorší případ ohraničený.
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(days) { day in
                            block(day)
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        // **Rozměr se měří, nevyjednává** (#361): obrazovka stojí ve `VStack`u okna, takže by
        // jeho průzkumné dotazy na pružnost šly skrz na `LazyVStack` dní.
        .fillingSlot()
        .background(Palette.surface)
    }

    // MARK: - Hlavička

    private var head: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: RailSection.activity.title)
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.5)
                Text(verbatim: subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            if let lastSuccess {
                Text(verbatim: "obnoveno \(lastSuccess.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
            }
        }
    }

    // MARK: - Blok dne

    private func block(_ day: ActivityFeedDay) -> some View {
        VStack(spacing: 0) {
            header(day)
            timeline(day)
        }
        .background(Palette.chrome, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private func header(_ day: ActivityFeedDay) -> some View {
        HStack(spacing: 6) {
            // Počet nepřečtených patří do nadpisu, ne k odznaku: na aktivní položce railu se
            // odznak nekreslí, protože by v tomhle railu překryl ikonu (návrh, poznámka 95).
            Text(verbatim: day.note.map { "\(day.title) · \($0)" } ?? day.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            // Odkaz jen u **prvního** bloku: v každém by to byl týž odkaz několikrát pod sebou.
            if day.id == days.first?.id {
                Button(action: openSettings) {
                    Text("co se hlásí ↗")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(AccentLinkButtonStyle())
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
    }

    /// Osa dne: svislá čára a na ní puntíky.
    ///
    /// Čára je **na pozadí**, ne prvek v každém řádku: `.tl::before` z návrhu jde přes celý blok
    /// a prvek na řádek by znamenal jeden prvek navíc na položku (#252 — co se dá spočítat, se
    /// nevyjednává).
    private func timeline(_ day: ActivityFeedDay) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(day.rows) { row in
                if row.isFirstSeen { SeenMarker(at: lastVisit, now: now) }
                ActivityRowView(event: row.event, now: now, open: open)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(alignment: .topLeading) { rail }
    }

    /// Svislá čára osy. `left: 30px` z návrhu je střed puntíku (18 odsazení + 12 poloviny
    /// dvacetičtyřky), takže se kreslí pod ním, ne vedle.
    private var rail: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 2)
            .padding(.vertical, 8)
            .padding(.leading, 29)
    }
}

/// Pruh `Tady jsem skončil` (#414).
///
/// **Popisek je obrácený proti konverzaci** (`Nové od tvé poslední návštěvy`), protože se řadí od
/// nejnovějšího jako commity (#316): pruh stojí **pod** novinkami, takže „nové od…“ by ukazovalo
/// na to, co už jsem viděl.
private struct SeenMarker: View {
    let at: Date?
    /// Hodiny obrazovky, ne `Date()` — viz `ActivityFeedView.now`.
    let now: Date

    var body: some View {
        // Verzálky jsou z návrhu (`.tl-new { text-transform: uppercase }`), ne velká písmena
        // v řetězci: text zůstává čitelný pro čtečku obrazovky a v repu se dá grepnout.
        HStack(spacing: 9) {
            Text("Tady jsem skončil".uppercased())
            Rectangle().fill(Palette.accent.opacity(0.45)).frame(height: 1)
            if let at {
                // Tentýž popisek jako ve větě v hlavičce — dvě různá formátování jednoho okamžiku
                // na jedné obrazovce vypadají jako dva různé okamžiky.
                Text(verbatim: Policy.visitLabel(at, now: now).uppercased())
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .tracking(1)
        .foregroundStyle(Palette.accent)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

/// Jeden řádek dění (#414).
///
/// **Bez pružné výšky** (#220, #375): puntík má rám 24 × 24 a obsah si výšku navrhuje sám. Klikatelný
/// je celý řádek — cíl je v něm napsaný, takže by tlačítko jen na šipce znamenalo cíl, na který se
/// nedá kliknout.
private struct ActivityRowView: View {
    let event: ActivityEvent
    /// Hodiny obrazovky, ne `Date()` — viz `ActivityFeedView.now`.
    let now: Date
    let open: (ActivityEvent) -> Void
    /// Odkaz ven otevírá **view**, ne store — jako v paletě ⌘K. Store se o prohlížeči nemá co
    /// dozvědět a jediný řádek, který ho potřebuje, je ten, který v okně nemá kam vést.
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: activate) { face }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(help)
            .accessibilityLabel(accessibilityLabel)
    }

    private func activate() {
        guard case .gitHub = Policy.destination(of: event.kind) else {
            open(event)
            return
        }
        guard let url = Policy.gitHubURL(of: event.pullRequest) else { return }
        openURL(url)
    }

    private var face: some View {
        HStack(alignment: .top, spacing: 8) {
            dot
            line
        }
    }

    private var dot: some View {
        Image(systemName: Policy.symbol(of: event.kind))
            .font(.system(size: 11))
            .foregroundStyle(tone)
            .frame(width: 24, height: 24)
            .background(Palette.chrome, in: .circle)
            .overlay { Circle().strokeBorder(tone, lineWidth: 1) }
    }

    /// Obsah řádku. **Zalomí se, když se nevejde** (`.tl-line` má `flex-wrap: wrap`), takže se
    /// dlouhý titulek PR nezkrátí na nic — ale cíl vpravo se od něj musí umět odtrhnout, jinak by
    /// se šipka zalomila doprostřed textu.
    private var line: some View {
        HStack(alignment: .center, spacing: 7) {
            FlowRow(spacing: 7, lineSpacing: 4) {
                Text(verbatim: event.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDimmed ? Palette.ink2 : Palette.ink)
                if let detail = event.detail {
                    Text(verbatim: "· \(detail)")
                        .font(.system(size: 12))
                        .foregroundStyle(isDimmed ? Palette.ink3 : Palette.ink2)
                        .lineLimit(1)
                }
                if let head = event.head {
                    ShaChip(sha: head)
                }
                if Policy.showsSilentChip(event.kind, announced: event.wasAnnounced) {
                    SilentChip()
                }
                // PR a autor jedním prvkem: `.tl-line` má mezeru 7 bodů, takže by tečku mezi nimi
                // odsadila od obojího a vypadala by jako oddělovač celého řádku.
                Text(verbatim: [event.pullRequest.description, event.author]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                time
            }
            Spacer(minLength: 8)
            destination
        }
        .frame(minHeight: 24, alignment: .center)
    }

    @ViewBuilder private var time: some View {
        if Policy.showsRelativeTime(of: event.at, now: now) {
            Text(event.at, format: .relative(presentation: .named))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
        } else {
            HStack(spacing: 3) {
                Text("v")
                Text(event.at, format: .dateTime.hour().minute())
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink3)
        }
    }

    /// Kam řádek vede. **Napsané, ne šipka bez obsahu** — a řádek, který vede jen ven, to přiznává
    /// i barvou (návrh, poznámka 92).
    private var destination: some View {
        Text(verbatim: destinationLabel)
            .font(.system(size: 11.5))
            .foregroundStyle(isDimmed ? Palette.ink3 : Palette.accent)
            .lineLimit(1)
    }

    private var destinationLabel: String {
        switch Policy.destination(of: event.kind) {
        case .tab(let tab): "→ \(tab.czechLabel)"
        case .gitHub: "GitHub ↗"
        }
    }

    /// Řádek, který do okna nevede, je celý ztlumený: PR z fronty odešel, takže se v seznamu
    /// nedohledá a fialový cíl by slíbil něco, co se nestane.
    private var isDimmed: Bool {
        Policy.destination(of: event.kind) == .gitHub
    }

    private var tone: Color {
        switch Policy.tone(of: event.kind) {
        case .neutral: Palette.line
        case .ok: Palette.ok
        case .critical: Palette.crit
        case .stale: Palette.stale
        case .accent: Palette.accent
        }
    }

    private var help: String {
        switch Policy.destination(of: event.kind) {
        case .tab(let tab): "Otevře \(event.pullRequest) a v něm záložku \(tab.czechLabel)"
        case .gitHub: "Otevře \(event.pullRequest) v prohlížeči — z fronty už odešel"
        }
    }

    /// Pro čtečku obrazovky celá věta: řádek se skládá z kusů, které samostatně neříkají nic.
    private var accessibilityLabel: String {
        [
            event.headline,
            event.detail,
            event.head,
            event.pullRequest.description,
            event.author,
            destinationLabel
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// Pilulka se sha (`.tl-line .sha`) — hlava, na které PR stojí teď.
private struct ShaChip: View {
    let sha: String

    var body: some View {
        // Zkrácená na sedm znaků jako všude jinde v okně; plná je v tooltipu, ať se dá porovnat.
        Text(verbatim: String(sha.prefix(7)))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 5)
            .background(Palette.raised, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineSoft, lineWidth: 1) }
            .help(sha)
    }
}

/// Chip `bez banneru` (`.tl-line .botchip`).
///
/// **Půlka hodnoty téhle obrazovky.** Záznam se plní i tehdy, když je aplikace mlčící — a tenhle
/// chip je to, co dělá z „nepřišlo mi to“ odpověď, ne domněnku.
private struct SilentChip: View {
    var body: some View {
        Text("bez banneru")
            .font(.system(size: 10))
            .foregroundStyle(Palette.ink3)
            .padding(.horizontal, 5)
            .background(Palette.raised, in: .rect(cornerRadius: 20))
            .help("O téhle události nedorazila notifikace — v záznamu je stejně.")
    }
}

/// Prázdný stav sekce (#414) — **tři různá prázdna**, viz `ActivityEmptyState`.
private struct ActivityFeedEmptyView: View {
    let state: ActivityEmptyState
    let openSettings: () -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        switch state {
        case .calm:
            EmptyStateView(
                nature: .calm,
                symbol: "checkmark",
                title: "Za poslední dny se nic nestalo",
                message: RailSection.activity.emptyExplanation
            )
        case .notificationsDenied:
            EmptyStateView(
                nature: .waiting,
                symbol: "bell.slash",
                title: "Notifikace jsou zakázané",
                message: """
                Bannery nechodí, ale tenhle seznam se plní dál. Povolit je jde jedině \
                v Nastavení systému → Oznámení → PRism.
                """,
                primary: .init(title: "Otevřít nastavení systému", run: openSystemSettings)
            )
        case .notificationsOff:
            EmptyStateView(
                nature: .waiting,
                symbol: "bell.slash",
                title: "Notifikace jsou vypnuté",
                message: """
                Bannery nechodí, ale tenhle seznam se plní dál — přepínače rozhodují o vyrušení, \
                ne o záznamu.
                """,
                primary: .init(title: "Otevřít nastavení", run: openSettings)
            )
        case .unreadable:
            // **Porucha, ne klid**: soubor tam byl a nepřečetl se, takže je historie ztracená.
            // „Nic se nestalo“ by nad tím lhalo.
            EmptyStateView(
                nature: .failure,
                symbol: "exclamationmark.triangle",
                title: "Záznam dění se nepodařilo přečíst",
                message: """
                To, co se stalo dřív, je ztracené. Nové události se zapisují dál, takže se seznam \
                za chvíli začne plnit znovu.
                """
            )
        }
    }
}
