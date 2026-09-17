import SwiftUI

/// Karta `Odpověď na tvoje review` (#523) — druhé kolo na jednom místě.
///
/// Stojí **nahoře v `Přehledu`, nad pruhem `Od tvé poslední návštěvy`**: ten odpovídá na „co
/// přibylo“, tahle na „co se stalo s tím, na co jsem se ptal“ — a to druhé se čte dřív, protože
/// je z toho hotová akce.
///
/// **Dvě karty, ne jedna.** Návrh (Z3) kreslí druhé kolo v šasi `.since`, tedy jako *podobu*
/// pruhu od minule. Slít je doopravdy do jedné by ale sundalo odrážku o přepsané historii, odznak
/// `nálezy zastaraly` i obě tlačítka toho pruhu — a zrovna po pushi autora jsou to ty věci, které
/// platí nejvíc. Zůstávají proto vedle sebe, každá nakreslená tak, jak ji návrh kreslí (sekce 60).
///
/// **Tón je akcent, ne okrová.** `--stale` znamená „platilo to, dneska už ne“ (proto ho má pruh od
/// minule); tahle karta říká opak — **je co udělat**, a pruh s návrhem verdiktu v ní je `.pill.run`,
/// tedy akcent. Dvě stejně okrové karty nad sebou by navíc splynuly v jednu.
struct ReviewReplyCardView: View {
    let card: ReviewReplyCard
    /// Předepsat schválení a otevřít potvrzení. **Nic neodesílá** — sheet je pořád ten dnešní.
    var approve: (() -> Void)?
    /// Otevřít vlákno, které zbývá. `nil` = nezbývá nic, tlačítko se nekreslí.
    var openRemaining: ((String) -> Void)?

    /// Šířka, kterou má karta k dispozici (#220). `nil` = nikdo ji nepředal.
    @Environment(\.availableWidth) private var available

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            rows
            if !card.caveats.isEmpty { caveats }
            actions
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.07))
        // Levý okraj je v návrhu **okraj rámečku** (`border-left: 3px`), takže se zaoblením
        // zatáčí — tatáž konstrukce jako u pruhu od minule: pozadí a `clipShape`, ne `overlay`
        // s obdélníkem, který by se v rozích usekl.
        .background(alignment: .leading) { Rectangle().fill(Palette.accent).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Palette.accent.mix(with: Palette.line, by: 0.55), lineWidth: 1)
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        HStack(spacing: 7) {
            // `↩` z návrhu: karta mluví o odpovědi na moje review, ne o čase.
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 12))
                .foregroundStyle(Palette.accent)
            Text(card.title)
                .font(.system(size: 12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let stamp = card.stamp {
                // Mono a `--ink-3`, jak to má návrh (`.since .hd .when`): je to údaj, ne věta.
                // Čas se sází **relativně a přepočítává sám** — hotový řetězec by zamrzl na tom,
                // kdy se poskládal.
                // **Skládá se `Text` + `Text`, ne interpolace do řetězce**: `"\(Text(…))"` vybere
                // `Text(String)`, takže se do popisku vysází `Text(storage: SwiftUI…)`. Bylo to
                // vidět na snímku běžící aplikace, ne v testech — proto tahle věta.
                (Text(verbatim: "prověřeno ")
                    + Text(stamp.checkedAt, format: .relative(presentation: .named))
                    + Text(verbatim: " · \(stamp.shortSha)"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
                    // **Zalomí se, neořeže.** Sha je identifikační údaj — `9c1…` je zrovna ta
                    // půlka, kvůli které tam stojí. V `Přehledu` širokém 380 bodů se titulek
                    // a razítko na jednu řádku nevejdou nikdy, takže je zalomení normální stav.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Řádky

    private var rows: some View {
        VStack(alignment: .leading, spacing: 3) {
            if card.foldedFixed > 0 { folded }
            // Identita je **uložená** (`Row.id` je identita vlákna z GitHubu), ne pořadí ani text:
            // dva komentáře se snadno složí do stejné věty a `id: \.self` by z nich udělal jeden
            // řádek (#361).
            ForEach(card.rows) { row in
                reply(row)
            }
        }
    }

    /// Sbalený přebytek opravených bodů — **počet, ne ořez** (`.lchip.more`, #390).
    private var folded: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            mark(.fixed)
            Text(verbatim: "+ \(Self.foldedLabel(card.foldedFixed))")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.ink3)
        }
    }

    /// `+ 2 další opravené body` — počet, ne ořez.
    static func foldedLabel(_ count: Int) -> String {
        Plural.czech(
            count,
            one: "další opravený bod",
            few: "další opravené body",
            many: "dalších opravených bodů"
        )
    }

    private func reply(_ row: ReviewReplyCard.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            mark(row.mark)
            // **Zalomí se, neořeže**: co se nevejde, je věta, kvůli které se na kartu kouká —
            // ukusnutá by z ní udělala hádanku. Panel `Přehledu` je v nejužším tabu 128 bodů
            // (viz `SinceLastVisitView`), takže zalomení je normální stav, ne výjimka.
            Text(Self.attributed(row))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Značka na začátku řádku. **Tři barvy, tři významy** — z palety, ne ze systému (#432).
    private func mark(_ mark: ReviewReplyCard.Mark) -> some View {
        Image(systemName: Self.symbol(mark))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Self.tint(mark))
            .frame(width: Self.markWidth, alignment: .center)
            .accessibilityLabel(Self.markLabel(mark))
    }

    static func symbol(_ mark: ReviewReplyCard.Mark) -> String {
        switch mark {
        case .fixed: "checkmark"
        case .answered: "arrowshape.turn.up.left"
        case .unanswered: "circle"
        }
    }

    static func tint(_ mark: ReviewReplyCard.Mark) -> Color {
        switch mark {
        case .fixed: Palette.ok
        case .answered: Palette.accent
        // Ztlumená, ne červená: `bez odpovědi` **není porucha** a už vůbec ne „ignoroval mě“ —
        // je to bod, ke kterému se nikdo nedostal.
        case .unanswered: Palette.ink3
        }
    }

    /// Popisek pro odečítání obrazovky — glyf sám o sobě neříká nic.
    static func markLabel(_ mark: ReviewReplyCard.Mark) -> String {
        switch mark {
        case .fixed: "opraveno"
        case .answered: "odpovězeno"
        case .unanswered: "bez odpovědi"
        }
    }

    private static let markWidth = 13.0
    private static let horizontalPadding = 12.0

    /// Části řádku na sazbu: místo tučně, moje věta normálně, co se s ní stalo ztlumeně.
    ///
    /// Jeden `Text`, ne tři vedle sebe — jinak by se každá část zalomila zvlášť a v úzkém
    /// `Přehledu` z řádku vznikly tři odstavce.
    static func attributed(_ row: ReviewReplyCard.Row) -> AttributedString {
        var text = AttributedString()
        var place = AttributedString(row.place)
        // `li b { color: --ink; font-weight: 580 }` — v repu se 580 i 620 překládá na `.semibold`.
        place.font = .system(size: 12, weight: .semibold)
        place.foregroundColor = Palette.ink
        text += place
        if !row.text.isEmpty {
            text += AttributedString(" · \(row.text)")
        }
        var note = AttributedString(" — \(row.note)")
        note.foregroundColor = Palette.ink3
        text += note
        return text
    }

    // MARK: - Co karta neví

    private var caveats: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(card.caveats.enumerated()), id: \.offset) { _, caveat in
                Text(.init(Policy.replyCaveatSentence(caveat)))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Řada ovládání

    /// Pruh s návrhem a tlačítka pod ním (`.rv-sinceacts`).
    ///
    /// **Zlomí se do sloupce, když se nevejde** — a rozhoduje o tom **spočítaná** šířka, ne
    /// `ViewThatFits`: odznak i popisky tlačítek jsou vodorovně pružné, takže se ve zúžené řadě
    /// radši zkrátí, než by nahlásily, že se nevejdou (viz `SinceLastVisitView.fits`).
    @ViewBuilder private var actions: some View {
        if Self.fits(card, in: available) {
            // **Pruh vlevo, tlačítka vpravo** (`.rpl-acts .sp` v návrhu): pruh je tvrzení
            // o stavu, tlačítka jsou akce — a v řadě, kde jsou vedle sebe natěsno, se čtou
            // jako tři stejně vážné volby.
            HStack(spacing: MiniButtonStyle.Metrics.spacing) {
                proposalPill
                Spacer(minLength: MiniButtonStyle.Metrics.spacing)
                buttons
            }
        } else {
            // Ve sloupci **Spacer nemá co dělat**: roztáhl by kartu na výšku o prázdné místo.
            VStack(alignment: .leading, spacing: MiniButtonStyle.Metrics.spacing) {
                proposalPill
                buttons
            }
        }
    }

    private var proposalPill: some View {
        Text(verbatim: card.proposalLabel)
            .lineLimit(1)
            .designPill(tint: Palette.accent, background: Palette.accentWeak)
            .help(Self.proposalHelp)
    }

    @ViewBuilder private var buttons: some View {
        if let openRemaining, let remaining = card.openRemaining {
            Button(remaining.label) { openRemaining(remaining.threadID) }
                .buttonStyle(.miniPrimary)
                .help("Přepne do Konverzace a rozbalí to vlákno")
        }
        if let approve {
            Button(card.approveLabel, action: approve)
                .buttonStyle(card.openRemaining == nil ? .miniPrimary : .mini)
                // Nápověda říká **co se stane**, ne co to znamená: „schválit“ u tlačítka, které
                // nic neodesílá, se dá číst jako odeslání.
                .help("Předepíše schválení do rozdělaného review a otevře potvrzení — odešle se"
                    + " teprve odtud")
        }
    }

    static let proposalHelp = "Návrh aplikace, ne odeslaný verdikt. Schválit se dá jedině"
        + " z potvrzení, kde je vidět celý payload."

    /// Vejde se řada na jeden řádek? `nil` šířka = nikdo ji nepředal, pak se kreslí v řadě.
    static func fits(_ card: ReviewReplyCard, in available: CGFloat?) -> Bool {
        guard let available else { return true }
        var widths = [TextWidth.pill(card.proposalLabel)]
        if let remaining = card.openRemaining {
            widths.append(TextWidth.miniButton(remaining.label, emphasis: .primary))
        }
        widths.append(TextWidth.miniButton(
            card.approveLabel,
            emphasis: card.openRemaining == nil ? .primary : .secondary
        ))
        let gaps = MiniButtonStyle.Metrics.spacing * Double(widths.count - 1)
        // Odsazení karty se odečítá tady, protože karta je ten, kdo ho přidává.
        return widths.reduce(0, +) + gaps <= available - 2 * horizontalPadding
    }
}

#Preview {
    let card = ReviewReplyCard(
        title: "Odpověď na tvoje review z 29. 8.",
        stamp: ReviewReplyCard.Stamp(
            checkedAt: Date().addingTimeInterval(-1800),
            headSha: "9c1de0212ab"
        ),
        rows: [
            ReviewReplyCard.Row(
                threadID: "1",
                mark: .fixed,
                place: "ř. 81",
                text: "prázdný fallback otočen na výjimku",
                note: "opraveno v 9c1de02"
            ),
            ReviewReplyCard.Row(
                threadID: "2",
                mark: .answered,
                place: "ř. 119",
                text: "batch endpoint pro předehřev",
                note: "odpověděl sykora-ji: „necháme na AJDA-570“"
            ),
            ReviewReplyCard.Row(
                threadID: "3",
                mark: .unanswered,
                place: "ř. 60",
                text: "nonce z konstruktoru",
                note: "bez odpovědi · řádek beze změny"
            )
        ],
        foldedFixed: 2,
        proposal: .comment(.unanswered(1)),
        approvalBody: nil,
        openRemaining: ReviewReplyCard.Remaining(threadID: "3", label: "Otevřít zbývající (ř. 60)"),
        caveats: []
    )
    return ReviewReplyCardView(card: card, approve: {}, openRemaining: { _ in })
        .padding()
        .frame(width: 620)
}
