import SwiftUI

/// Co se na PR stalo od poslední návštěvy (#173).
///
/// Stojí **nahoře v `Přehledu`**, nad dlaždicemi s fakty: je to jediná věc na obrazovce, která
/// odpovídá na otázku „co je tu nového“, a ta se ptá dřív než „jak to stojí“.
///
/// Ukazuje se, jen když **opravdu něco přibylo**. Trvalý pruh s „nic nového“ by z obrazovky
/// ubíral místo a po týdnu by se přestal číst — na rozdíl od stavového řádku, kde je trvalost
/// smyslem, protože se tam hlásí zdraví aplikace.
///
/// Sazba je z návrhu (`.since`, #226 a #284): okrový tón (`--stale`), levý okraj 3 body, obrys
/// smíchaný s tónem, poloměr 7 jako u ostatních karet `Přehledu`.
///
/// **Barva je jedna, ne dvě** — do #226 byl blok systémově modrý a při přepsané historii žlutý.
/// Obojí bylo mimo paletu okna: modrá je systémový akcent, kdežto okno stojí na fialové z návrhu
/// (#180), a systémová žlutá je **výstraha**. `--stale` znamená „platilo to, dneska už ne“, což je
/// přesně to, co tenhle blok říká — a proto ho návrh kreslí okrový vždycky.
///
/// **Odrážky se sázejí po částech** (#284): tučně to, co se stalo, ztlumeně kdo a kdy, sha jako
/// kód. Skládá je `SinceLastVisitLines` — mimo view, aby se text testoval bez kreslení.
///
/// **Časový údaj a `×` v návrhu nejsou**, v aplikaci ano, a zůstávají: bez `×` by pruh visel,
/// dokud je aplikace spuštěná (viz `dismiss`), a bez času by „od tvé poslední návštěvy“ neřeklo
/// od kdy. Obojí sedí v hlavičce vpravo, tedy tam, kde návrh kreslí `.when` — přibývá k němu
/// křížek, ne druhé místo.
struct SinceLastVisitView: View {
    let changes: VisitChanges
    /// Proti čemu se to počítá. Bez toho by „od tvé poslední návštěvy“ neřeklo od kdy.
    let since: Date?
    /// Zastaralo něco, co mám na obrazovce — nálezy, nebo rozdělané review? Počítá store, ne
    /// tenhle typ; je to tvrzení o uložených datech, ne o časové ose.
    ///
    /// Rozhoduje **jen o nabídce pustit review znovu**. Co se v pruhu tvrdí o nálezech, nese
    /// `hasStaleFindings` — to jsou dvě různé věci a slít je znamená slíbit jednu tam, kde platí
    /// druhá.
    var isStale = false
    /// Jsou **nálezy** (aspoň jeden) proti commitu, který na větvi už není?
    ///
    /// Jediný zdroj je `AppStore.staleFindings(for:)`, tedy totéž, z čeho se kreslí hlavička
    /// `StaleHeadView` nad taby. Odznak tak nemůže tvrdit něco jiného než ona — a nad PR, na
    /// kterém review nikdy neběželo, se nemá čím rozsvítit.
    var hasStaleFindings = false
    /// Nová hlava PR, pokud se od minule posunula. Je to **druhý zdroj** vedle časové osy:
    /// `TimelineEvent.at` je u commitu datum commitu, ne pushnutí, takže po rebase commity
    /// z „od minule“ vypadnou — porovnání sha na to nesáhne.
    var movedHead: String?
    var rerun: (() -> Void)?
    /// Ukázat jen to, co od minule přibylo (#284). `nil` = **nedá se**, takže se tlačítko
    /// nenabídne; rozhoduje o tom `Policy.incrementalDiff`, ne tenhle typ.
    var showAdded: (() -> Void)?
    /// „Přečteno“. Bez toho by pruh visel, dokud je aplikace spuštěná — správně napoprvé,
    /// otravně napopáté.
    var dismiss: (() -> Void)?

    /// Šířka, kterou má pruh k dispozici (#220). `nil` = nikdo ji nepředal.
    @Environment(\.availableWidth) private var available

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            VStack(alignment: .leading, spacing: 3) {
                // Identita je **pořadí**, ne text: dvě položky se snadno složí do stejné věty
                // (dvě review od téhož autora se stejným verdiktem) a `id: \.self` by z nich
                // udělal jeden řádek.
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    bullet(line)
                }
            }
            actions
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.stale.opacity(0.09))
        // Pruh je v návrhu **levý okraj rámečku** (`border-left: 3px`), takže se zaoblením
        // zatáčí. `overlay` s obdélníkem by z něj udělal rovnou tyčku useknutou v rozích —
        // proto pozadí a `clipShape`, které mu ten oblouk dá.
        .background(alignment: .leading) { Rectangle().fill(Palette.stale).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 7))
        // Obrys **je**, a to je půlka problému, kterou to řeší: bez něj plavala plná barevná
        // plocha vedle obrysových karet `Přehledu`. Barva je obrys smíchaný s tónem bloku,
        // jak to má návrh (`color-mix(--stale 45%, --line)`).
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Palette.stale.mix(with: Palette.line, by: 0.55), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            // `⟲` z návrhu, ne hodiny: pruh mluví o tom, co se s větví stalo, ne o čase.
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12))
                .foregroundStyle(Palette.stale)
            Text("Od tvé poslední návštěvy")
                .font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 8)
            if let since {
                // Mono a `--ink-3`, jak to má návrh (`.since .hd .when`): je to údaj, ne věta.
                Text(since, format: .relative(presentation: .named))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink3)
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                // Nápověda říká **důsledek**, ne jméno ikony: křížek u oznámení se dá číst
                // i jako „zahodit ty změny“, a to by tohle tlačítko nikdy neudělalo.
                .help("Označit za přečtené — pruh zmizí, dokud nepřibude něco dalšího")
                .accessibilityLabel("Označit za přečtené")
            }
        }
    }

    // MARK: - Odrážky

    /// Odrážka: puntík v pruhu široké 17 bodů (`ul { padding-left: 17px }`) a za ním věta, která
    /// se v úzkém tabu zalomí pod sebe, ne za puntík.
    private func bullet(_ line: SinceLastVisitLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "•")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .frame(width: Self.bulletIndent, alignment: .center)
            Text(Self.attributed(line))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let bulletIndent = 17.0

    /// Části odrážky na sazbu.
    ///
    /// **Sha je podklad za písmem, ne kapsle s odsazením** — a je to tatáž volba, jakou už udělal
    /// inline kód v sazbě Markdownu (`MarkdownInlineText.highlightCode`, #279). Návrh ho kreslí
    /// jako `<code>` s poloměrem 5 a odsazením 1/5 bodu, jenže `AttributedString` umí u běhu
    /// nastavit barvu pozadí, ne jeho výplň a rádius — kapsle by znamenala kreslit každou sha
    /// jako vlastní view, a tím rozpadlé zalomení uprostřed věty. Odrážka je v úzkém `Přehledu`
    /// (128 bodů) zalomená vždycky, takže je to výměna „zaoblené rohy“ za „věta se dá přečíst“.
    ///
    /// Barva podkladu i písma je z návrhu (`code { background: --accent-weak; color: --ink }`),
    /// velikost z jednoho zdroje se sazbou Markdownu (`0,88em` z 12 je 10,5).
    static func attributed(_ line: SinceLastVisitLine) -> AttributedString {
        var text = AttributedString()
        for part in line.parts {
            switch part {
            case .plain(let value):
                text += AttributedString(value)
            case .strong(let value):
                var run = AttributedString(value)
                // `li b { color: --ink; font-weight: 580 }` — v repu se 580 i 620 překládá
                // na `.semibold`, jako u titulku pruhu nad odrážkami.
                run.font = .system(size: 12, weight: .semibold)
                run.foregroundColor = Palette.ink
                text += run
            case .sha(let value):
                var run = AttributedString(value)
                run.font = .system(size: MarkdownTypography.codeSize(base: 12), design: .monospaced)
                run.foregroundColor = Palette.ink
                run.backgroundColor = Palette.accentWeak
                text += run
            }
        }
        return text
    }

    // MARK: - Řada ovládání

    /// Odznak a tlačítka pod odrážkami (`.since .row`).
    ///
    /// Do #284 tu byla **věta a tlačítko** („Nálezy i rozdělané review jsou proti commitu, který
    /// na větvi už není.“ + `Pustit review znovu`) a celá řada visela na `isStale`. Mělo to dvě
    /// vady, které #284 vyjmenoval: po přepsané historii se nenabídlo **nic**, když na PR ještě
    /// žádné nálezy nebyly — a přitom pustit review je zrovna tehdy ta rozumná další věc —
    /// a věta zabírala dva řádky tam, kde návrh má odznak o třech slovech.
    ///
    /// **Prázdná se nekreslí vůbec**, ani jako mezera: pruh se nesmí ukázat prázdný.
    @ViewBuilder private var actions: some View {
        if !parts.isEmpty {
            // **Zlomí se do sloupce, když se nevejde** — a rozhoduje o tom **spočítaná** šířka,
            // ne `ViewThatFits`. Ten se u téhle řady spolehnout nedá: odznak i popisky tlačítek
            // jsou vodorovně pružné, takže se ve zúžené řadě radši zkrátí, než by nahlásily, že
            // se nevejdou — a v pruhu by pak stálo `Pust…`. Podrobnosti u `TextWidth`.
            if Self.fits(parts, in: available) {
                HStack(spacing: MiniButtonStyle.Metrics.spacing) { row }
            } else {
                VStack(alignment: .leading, spacing: MiniButtonStyle.Metrics.spacing) { row }
            }
        }
    }

    @ViewBuilder private var row: some View {
        if hasStaleFindings { Self.stalePill }
        if offersRerun, let rerun {
            Button(Self.rerunLabel, action: rerun)
                .buttonStyle(.miniPrimary)
        }
        if let showAdded {
            Button(Self.showAddedLabel, action: showAdded)
                .buttonStyle(.mini)
                .help("Diff jen toho, co od tvé poslední návštěvy přibylo — otevře se v tabu Změněné soubory")
        }
    }

    /// Co v řadě zrovna stojí. Kombinací je osm, takže se šířka počítá z výčtu, ne z osmi větví.
    enum ActionPart: CaseIterable {
        case badge
        case rerun
        case showAdded
    }

    private var parts: [ActionPart] {
        var parts: [ActionPart] = []
        if hasStaleFindings { parts.append(.badge) }
        if offersRerun, rerun != nil { parts.append(.rerun) }
        if showAdded != nil { parts.append(.showAdded) }
        return parts
    }

    /// Vejde se řada na jeden řádek? `nil` šířka = nikdo ji nepředal, pak se kreslí v řadě.
    static func fits(_ parts: [ActionPart], in available: CGFloat?) -> Bool {
        guard let available, !parts.isEmpty else { return true }
        let gaps = MiniButtonStyle.Metrics.spacing * Double(parts.count - 1)
        // Odsazení pruhu se odečítá tady, protože pruh je ten, kdo ho přidává — volající o něm
        // nemá jak vědět.
        return parts.map(width(of:)).reduce(0, +) + gaps <= available - 2 * horizontalPadding
    }

    static func width(of part: ActionPart) -> CGFloat {
        switch part {
        case .badge: badgeWidth
        case .rerun: TextWidth.miniButton(rerunLabel, emphasis: .primary)
        case .showAdded: TextWidth.miniButton(showAddedLabel, emphasis: .secondary)
        }
    }

    /// Popisky **nejsou `private`**: měří je `width(of:)` a **kontroluje je test** proti tomu, co
    /// se doopravdy nakreslí (`SinceLastVisitActionsTests`). Opsat je v testu by znamenalo měřit
    /// jiný text než ten v okně.
    static let rerunLabel = "Pustit review znovu"
    static let showAddedLabel = "Ukázat, co přibylo"
    static let badgeLabel = "nálezy zastaraly"
    private static let horizontalPadding = 12.0
    /// Odznak i s odsazením kapsle (`.pill { padding: 2px 7px }`) — řez a odsazení bere
    /// z `DesignPill`, tedy z toho, čím se kapsle doopravdy kreslí (#348).
    private static let badgeWidth = TextWidth.pill(badgeLabel)

    /// Pustit review znovu se nabízí, i když **žádné nálezy zatím nejsou** — po přepsané historii
    /// je to ta rozumná další věc. Odznak vedle se v tom případě nerozsvítí, protože by tvrdil
    /// něco, co data neunesou.
    private var offersRerun: Bool {
        isStale || !changes.forcePushes.isEmpty
    }

    /// `.pill.stale` z návrhu: mono, malé, okrové na vlastním tichém podkladu.
    ///
    /// **`static` a `internal`, ať se dá změřit** — test porovnává `width(of: .badge)` s tím, co
    /// se doopravdy nakreslí, a kdyby si odznak skládal sám, měřil by jinou věc než okno.
    static var stalePill: some View {
        Text(verbatim: Self.badgeLabel)
            .lineLimit(1)
            .designPill(tint: Palette.stale, background: Palette.stale.opacity(0.16))
            .help("Nálezy i rozdělané review jsou proti commitu, který na větvi už není.")
    }

    private var lines: [SinceLastVisitLine] {
        SinceLastVisitLines(changes: changes, movedHead: movedHead).lines
    }
}

#Preview {
    let actor = EventActor(login: "odinuv", avatarURL: nil, isBot: false)
    return VStack(spacing: 16) {
        SinceLastVisitView(
            changes: VisitChanges(
                commits: [
                    TimelineEvent(
                        id: "1",
                        kind: .commit(oid: "9c1de0212ab", headline: "fix: nevracet prázdný secret"),
                        actor: actor,
                        at: Date().addingTimeInterval(-3600)
                    )
                ],
                forcePushes: [
                    TimelineEvent(
                        id: "2",
                        kind: .forcePushed(before: "4f2ac9188cd", after: "9c1de0212ab"),
                        actor: actor,
                        at: Date().addingTimeInterval(-3600)
                    )
                ],
                events: [],
                reviews: [],
                comments: []
            ),
            since: Date().addingTimeInterval(-86400),
            isStale: true,
            hasStaleFindings: true,
            rerun: {},
            showAdded: {}
        )
    }
    .padding()
    .frame(width: 620)
}
