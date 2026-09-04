import SwiftUI

/// Sekce railu `Dění` (#414) — co se na pull requestech stalo, když jsem se nekoukal.
///
/// **Sekce, ne popover** — a od #443 **taky blok na dashboardu**. Do #443 tady stálo, že dění
/// blokem na dashboardu není, protože by z něj byla ukázka a ne místo, kde se dá zůstat; ukázalo
/// se, že ta ukázka je právě to, co chybí. Sekce se do railu musí **jít**, tedy napřed vědět, že je
/// do čeho koukat — a odznak v railu říká počet, ne co se stalo.
///
/// **Co se tím nemění**: rolovat, číst po dnech a dohledávat se chodí sem. Blok na dashboardu
/// (`DashboardActivity`, návrh sekce 31) je ukázka a rozcestník — bez vlastního prázdna, bez
/// vlastního pruhu poslední návštěvy a bez vlastního řádku. Kdyby si je pořídil, jsou to dvě dění.
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

    /// Osa dne (`ActivityTimeline`, sdílená s blokem na domácí záložce od #443). Sem se do ní
    /// vkládá i pruh `Tady jsem skončil` — v bloku žádný není, protože osm řádků (do #515 pět)
    /// nemá co dělit na dvě hromádky.
    ///
    /// **Den nese hlavička bloku a místo je tu na celou událost**, takže řádek zůstává
    /// `ActivityRowPlace.section` — úzký tvar i den u času má jen ten blok.
    private func timeline(_ day: ActivityFeedDay) -> some View {
        ActivityTimeline {
            ForEach(day.rows) { row in
                if row.isFirstSeen { SeenMarker(at: lastVisit, now: now) }
                ActivityRowView(event: row.event, now: now, open: open)
            }
        }
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

/// Prázdný stav sekce (#414) — **čtyři různá prázdna**, viz `ActivityEmptyState`.
///
/// **Tlačítka jsou tady schválně, ne na dashboardu** (#443): odpovídají na „proč je tu prázdno“
/// a spraví se jimi to, kvůli čemu je — a to je obsah pro obrazovku, na kterou jsem přišel
/// schválně. Na dashboardu z nich zbude jedna věta (`Policy.dashboardActivity`).
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
