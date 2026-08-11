import SwiftUI

/// Nálezy k jednomu řádku, zavěšené pod ním — jako review komentář u kódu.
///
/// Texty se **neslučují**: když se dva reviewery potkají na jednom řádku, jsou v bublině
/// pod sebou a odznak říká, kolik jich je. Nesouhlas dvou reviewerů je informace.
///
/// **Blokující nález je rozbalený rovnou, ostatní jsou značka na hraně řádku** (#185). Rozhoduje
/// o tom `disclosure`, kterou skládá `Policy` — tady se jen kreslí. Značka je tentýž pruh jako
/// hlavička rozbalené bubliny, takže kliknutím nic nepřeskočí: přibude pod ní obsah.
struct FindingBubbleView: View {
    let group: FindingGroup
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    /// `false` = řádek nálezu v diffu není. Bublina pak visí u hlavičky souboru a nabízí
    /// ten řádek dotáhnout.
    var isAnchored = true
    var reveal: ((ClosedRange<Int>) -> Void)?
    /// Skočilo se sem právě z tabulky? Samotný scroll nepoví, kam mířil.
    var isHighlighted = false
    /// Převzetí nálezu do rozdělaného review.
    var draft = FileDraftActions()
    /// Odmítnutí a vrácení nálezu (#113). `nil` = bublina je jen ke čtení, což je stav, ve
    /// kterém se staví v testech skládání řádků a v náhledech.
    var actions: FindingActions?
    /// Odsazení do sloupce s obsahem. Ve split pohledu je v buňce jedno číslo řádku místo
    /// dvou, takže je kratší — stejný parametr jako u `ThreadBubbleView`.
    var indent: Double = DiffLineView.contentInset(for: .unified)
    /// Jak je bublina rozbalená (#185). Výchozí `.expanded` platí tam, kde o rozbalení
    /// rozhoduje volající — tabulka nálezů kreslí bublinu až po rozbalení řádku.
    var disclosure: FindingDisclosure = .expanded
    /// Překliknutí rozbalení. `nil` = rozbalení řídí někdo jiný (tabulka) nebo nikdo (náhledy),
    /// a pruh se pak nekreslí jako tlačítko.
    var toggle: (() -> Void)?

    /// Kolik řádků kolem nálezu se ukáže, když si o to uživatel řekne. Samotný řádek bez
    /// okolí se čte špatně.
    private static let context = 3

    /// Rozbalení po zohlednění **dat**: skupina, ze které nezbyl platný nález, je odmítnutá, ať
    /// si volající řekl cokoli. Bez toho by ji tabulka (která rozbalení řídí sama) mohla vykreslit
    /// jako rozbalenou a sbalená značka by naopak schovala `Vrátit`, tedy jediné, co se s
    /// odmítnutým nálezem dá udělat.
    private var state: FindingDisclosure {
        group.activeFindings.isEmpty ? .dismissed : disclosure
    }

    var body: some View {
        // Odznak závažnosti se skládá **jednou za bublinu**: jde přes `activeFindings`, což je
        // filtr, a bublina se překresluje i při přejezdu myší (#224).
        let badge = Policy.severityBadge(of: group, categories: blockingCategories)
        VStack(alignment: .leading, spacing: 0) {
            if showsMark { mark(badge) }
            if state != .collapsed {
                if showsMark { separator }
                details
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **Neutrální plocha a barevná hrana**, jak to má návrh (`.inline-find`): závažnost nese
        // proužek, obrys a puntík, ne podbarvení celé bubliny. Do #185 měl blokující nález
        // červené pozadí — vedle přidaného řádku diffu, který je taky barevný, z toho byla
        // druhá barevná plocha na jednom místě.
        .background(Palette.chrome, in: .rect(cornerRadius: 7))
        .overlay(alignment: .leading) { Rectangle().fill(accent).frame(width: 3) }
        .clipShape(.rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(border, lineWidth: 1) }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(.tint, lineWidth: isHighlighted ? 2 : 0)
        }
        .animation(.easeOut(duration: 0.2), value: isHighlighted)
        .padding(.leading, indent)   // odsazení do sloupce s obsahem, vedle čísel řádků
        .padding(.trailing, 16)
        .padding(.vertical, 4)
    }

    /// Kreslí se pruh se značkou?
    ///
    /// Sbalená bublina je **jen** on, takže bez něj by nebylo nic. Rozbalená ho má tehdy, když
    /// se dá sbalit — v tabulce nálezů rozbalení řídí řádek nad bublinou, takže by tam byl druhý
    /// ovladač téhož a hlavička by v ní psala podruhé to, co je ve sloupcích.
    ///
    /// Odmítnutá skupina ho nemá vůbec: rozbalovat u ní není co (`FindingDisclosure.dismissed`)
    /// a její obsah **je** jeden řádek na nález.
    private var showsMark: Bool {
        guard state != .dismissed else { return false }
        return toggle != nil || state == .collapsed
    }

    /// Mají jednotlivé nálezy vlastní hlavičku?
    ///
    /// **Když je nález jeden, říká ji značka** — kategorie, verdikt a reviewer jsou pak vlastností
    /// celé bubliny a uvnitř by stály podruhé. Jenže značka se kreslí jen tam, kde se dá sbalit:
    /// v tabulce nálezů (kde rozbalení řídí řádek) žádná není, takže by hlavička zmizela úplně
    /// a s ní verdikt. Podmínka je proto **„buď značka, nebo hlavičky“**, ne „jeden nález“.
    private var showsEntryHeaders: Bool {
        group.findings.count > 1 || !showsMark
    }

    /// Linka mezi pruhy — `--line-soft` z palety, jako oddělovače uvnitř ploch všude jinde
    /// v okně. `Divider()` si bere barvu ze systému a vedle karty vlákna vypadal jako cizí.
    private var separator: some View {
        Rectangle().fill(Palette.lineSoft).frame(height: 1)
    }

    // MARK: - Značka

    /// Pruh, ze kterého se pozná, co v bublině je, aniž by se rozbalovala.
    ///
    /// Klikací celý, ne jen šipka: sbalená bublina je úzký pruh a trefit se do deseti bodů šipky
    /// je zbytečná práce — tatáž úvaha jako u hlavičky vlákna.
    private func mark(_ badge: FindingSeverityBadge) -> some View {
        Button {
            toggle?()
        } label: {
            HStack(spacing: 6) {
                if toggle != nil {
                    Image(systemName: state == .collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.ink3)
                }
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                severity(badge)
                if group.agreement > 1 { pill("\(group.agreement)×", color: Palette.accent) }
                // **I ve sbalené značce**, a je to podmínka, ne ozdoba: nezakotvená bublina visí
                // u hlavičky souboru, takže bez odznaku vypadá jako nález na prvním řádku hunku.
                // Věta „řádek v diffu není“ je až v obsahu, tedy za kliknutím — a utnutá pravda
                // nesmí vypadat jako úplná ani na jeden pohled (tatáž úvaha jako u zkráceného
                // vlákna).
                if !isAnchored {
                    pill("mimo diff", color: Palette.ink2)
                        .help("Řádek nálezu v diffu není — bublina proto visí u hlavičky souboru.")
                }
                // **I ve sbalené značce** (#150): nálezy, které neblokují, jsou v diffu sbalené,
                // takže by za kliknutím zůstalo zrovna to, kvůli čemu se kontrola pouštěla.
                if let status = markStatus {
                    pill(status.verdict.label, color: status.verdict.tint)
                        .help(status.help)
                }
                headline(strikesFindingText: badge.strikesFindingText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(toggle == nil)
        .help(markHint)
        .accessibilityLabel(markHint)
    }

    /// Odznak závažnosti — `blokuje`, a od #150 i `vyřešeno` z kontroly nových commitů.
    ///
    /// Sází se na **dvou** místech (ve značce nad obsahem a v hlavičce nálezu uvnitř), takže je na
    /// jednom místě v kódu — a co v něm stojí, rozhoduje `Policy`, ne tohle view. `vyřešeno` je
    /// **před** `blokuje`, protože odpovídá na „musím se na to ještě koukat“; `blokuje` za ním
    /// zůstává, protože je to fakt, kdežto `vyřešeno` je tvrzení modelu.
    @ViewBuilder private func severity(_ badge: FindingSeverityBadge) -> some View {
        switch badge {
        case .resolved(let status, let blocking):
            pill(FindingSeverityBadge.resolvedLabel, color: FindingSeverityBadge.resolvedTint)
                .help(status.help)
            if blocking { pill("blokuje", color: Palette.crit) }
        case .blocking:
            pill("blokuje", color: Palette.crit)
        // Odmítnutá skupina značku nekreslí vůbec (`showsMark`) a odmítnutý nález má vlastní řádek
        // s důvodem, takže tady není co ukázat.
        case .dismissed, .none:
            EmptyView()
        }
    }

    /// Co je ve značce napsané, rozhoduje **počet nálezů ve skupině**:
    ///
    /// - **jeden** (běžný případ) → celá hlavička nálezu, jak ji má návrh: kategorie, verdikt,
    ///   reviewer. Uvnitř se pak nekreslí podruhé.
    /// - **víc** → kolik jich je. Kategorie, verdikt ani reviewer nejsou vlastnost skupiny —
    ///   liší se po nálezech, takže si je nesou jednotlivé hlavičky uvnitř.
    ///
    /// A ve sbaleném stavu k tomu **náhled textu**. Bez něj by značka říkala „tady něco je“, ale
    /// ne co — tedy přesně to, kvůli čemu by se rozbalovala naslepo.
    @ViewBuilder private func headline(strikesFindingText: Bool) -> some View {
        if let finding = representative, group.findings.count == 1 {
            attributes(of: finding)
        } else if let count = countLabel {
            Text(verbatim: count)
                .font(.caption2)
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
        }
        if state == .collapsed, let preview {
            Text(verbatim: preview)
                // Náhled **je** text nálezu, takže se přeškrtává s ním (#150) — sbalená značka
                // jinak jako jediná tvrdila, že se nic nezměnilo.
                .strikethrough(strikesFindingText, color: Palette.ink3)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                // Náhled si o místo říká dřív než verdikt a reviewer: v úzkém okně se ořezává
                // to, co je nejmíň užitečné, ne to, kvůli čemu se značka čte.
                .layoutPriority(1)
        }
    }

    /// Kolik nálezů ve skupině je — a jen tehdy, když to odznak `2×` neříká už sám.
    ///
    /// Shoda počítá **reviewery**, počet **nálezy**, takže se ta dvě čísla rozcházejí (jeden
    /// reviewer se dvěma nálezy na řádku má `2 nálezy` a shodu 1). Když jsou stejná, `2× 2 nálezy`
    /// vedle sebe je totéž dvakrát.
    private var countLabel: String? {
        guard group.findings.count != group.agreement else { return nil }
        return Plural.czech(group.findings.count, one: "nález", few: "nálezy", many: "nálezů")
    }

    /// Náhled do sbalené značky — **krátká věta, když ji reviewer napsal**, jinak začátek
    /// shrnutí. `shortSummary` je přesně na tohle: jeden řádek do seznamu.
    private var preview: String? {
        guard let finding = representative else { return nil }
        let text = finding.shortSummary ?? finding.summary
        return text.isEmpty ? nil : text
    }

    /// Nález, který za skupinu mluví ve značce — první **platný**. Odmítnutý by za ni mluvit
    /// nesměl: značka by nesla kategorii nálezu, kterému nevěřím.
    private var representative: Finding? {
        group.activeFindings.first
    }

    /// Stav z kontroly do značky (#150) — **jen u skupiny s jediným platným nálezem, a jen když ho
    /// neřekl odznak závažnosti**.
    ///
    /// U víc nálezů na jednom řádku by odznak mluvil za všechny, a to je zrovna ten případ, kdy
    /// se výsledky liší: jeden nález může být opravený a druhý pořád platit. Tam si stav nese
    /// každá položka uvnitř bubliny.
    ///
    /// `vyřešeno` stojí v odznaku závažnosti pár bodů vlevo, takže by tu byly dvě kapsle o jedné
    /// věci; plný popisek `kontrola: vyřešeno` se místo toho kreslí **uvnitř** bubliny, kde je pro
    /// něj místo — a s ním i to, kdo „vyřešeno“ tvrdí. `pořád platí` a `nejasné` závažnost nemění,
    /// takže ve značce zůstávají.
    private var markStatus: RecheckStatus? {
        let active = group.activeFindings
        guard active.count == 1, let finding = active.first else { return nil }
        guard let status = group.recheck(of: finding), status.verdict != .resolved else { return nil }
        return status
    }

    private var markHint: String {
        switch state {
        case .collapsed: "Rozbalit nález"
        case .expanded: "Sbalit nález"
        case .dismissed: "Odmítnutý nález"
        }
    }

    // MARK: - Obsah

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isAnchored { missingLine }
            if group.agreement > 1 { agreementNote }
            ForEach(Array(group.findings.enumerated()), id: \.offset) { index, finding in
                if index > 0 { separator }
                entry(finding)
            }
        }
        .padding(10)
    }

    /// Nález mimo diff. Reviewer čte celý pracovní strom, takže tohle není chyba — jen se
    /// k tomu musí dotáhnout kód, který v diffu není.
    @ViewBuilder private var missingLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let line = group.line {
                Text(verbatim: "Řádek \(line) v diffu není — reviewer ho četl v souboru.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reveal {
                    // Tlačítko, ne odkaz (#283) — v bublině, kde jsou ostatní akce plochy, byl
                    // modrý text jediná věc, u které nebylo poznat, že se dá zmáčknout.
                    Button("Zobrazit ho") {
                        reveal(max(1, line - Self.context)...(line + Self.context))
                    }
                    .buttonStyle(.mini)
                }
            } else {
                Text("Nález se váže k celému souboru, ne ke konkrétnímu řádku.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Odmítnutý nález se **sbalí, nezmizí** (#113). Mizející nález je v tomhle okně nejhorší
    /// vzor: schovaný se nedá přečíst a nedá se odlišit od neexistujícího — a tady o důvod
    /// víc, protože to schování je moje rozhodnutí, takže musím mít jak zkontrolovat, co jsem
    /// odmítl. Ze stejného důvodu tu není přepínač „schovat odmítnuté“.
    @ViewBuilder private func entry(_ finding: Finding) -> some View {
        if let dismissal = group.dismissal(of: finding) {
            dismissed(finding, dismissal)
        } else {
            active(finding)
        }
    }

    private func active(_ finding: Finding) -> some View {
        // Stav z kontroly se čte **jednou na nález**: `group.recheck(of:)` skládá klíč, a ten je
        // řetězec (#224). Odznak i přeškrtnutí textu se pak řídí tímtéž.
        // Sem se odmítnutý nález nedostane (má vlastní větev), takže `dismissal` je `nil`.
        let status = group.recheck(of: finding)
        let badge = Policy.severityBadge(
            isBlocking: Policy.isBlocking(finding, categories: blockingCategories),
            recheck: status,
            dismissal: nil
        )
        return VStack(alignment: .leading, spacing: 4) {
            // Hlavička jen tehdy, když ji neřekla značka nad bublinou. U jednoho nálezu jsou
            // kategorie, verdikt a reviewer vlastností celé bubliny, takže by se psaly dvakrát.
            if showsEntryHeaders {
                HStack(spacing: 6) {
                    severity(badge)
                    attributes(of: finding)
                    Spacer()
                }
            }
            // Přeškrtnuté **jen shrnutí nálezu** (#150). Celý řádek ztlumit patří odmítnutí (#113),
            // za kterým stojí člověk — tvrzení modelu ten obrázek dostat nesmí.
            Text(finding.summary)
                .strikethrough(badge.strikesFindingText, color: Palette.ink3)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let status { recheck(status) }
            if let scenario = finding.failureScenario, !scenario.isEmpty {
                DisclosureGroup("Kdy to selže") {
                    Text(scenario)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
            footer(of: finding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Co o nálezu řekla kontrola z minula (#150) — odznak a věta pod textem nálezu.
    ///
    /// **Nález nemizí ani se nepřesouvá.** „Vyřešeno“ je tvrzení modelu, ne fakt; sundat nález
    /// smí jedině odmítnutí (#113), za kterým stojí člověk. Kdyby ho odznak schoval, přišel bych
    /// o něj tím, že se modelu něco zdálo — a to je nejdražší chyba, jakou tohle okno umí.
    ///
    /// U `vyřešeno` se ten odznak kreslí **vždycky**, i když závažnost nad bublinou říká
    /// `vyřešeno`: krátké slovo v odznaku závažnosti neříká, kdo to tvrdí, a `kontrola: …` je
    /// jediné místo, kde je to vidět bez najetí myší.
    @ViewBuilder private func recheck(_ status: RecheckStatus) -> some View {
        // Odznak ze značky se čte **jednou**: `activeFindings` je filtr, takže druhé volání je
        // další průchod skupinou při každém překreslení bubliny (#224). U `vyřešeno` je `nil`
        // schválně — značka ho nese jako závažnost, ne jako odznak kontroly.
        let inMark = markStatus != nil
        // Prázdný řádek se nekreslí: u jediného nálezu bez věty odznak nese značka nad bublinou.
        if !inMark || status.note != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Odznak jen tehdy, když ho značka neřekla — u jednoho nálezu je to vlastnost celé
                // bubliny a psal by se dvakrát. Věta k němu patří sem vždycky: do značky se
                // nevejde a je to to jediné, z čeho se pozná, jak k verdiktu došel.
                if !inMark {
                    pill(status.verdict.label, color: status.verdict.tint)
                }
                if let note = status.note {
                    Text(verbatim: note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .help(status.help)
        }
    }

    /// Kategorie, verdikt a reviewer — v návrhu jeden řádek hlavičky. Sází se na dvou místech
    /// (ve značce u jednoho nálezu, v hlavičce uvnitř u víc nálezů), a proto na jednom místě
    /// v kódu: dvě sazby téhož by se rozešly.
    @ViewBuilder private func attributes(of finding: Finding) -> some View {
        if let category = finding.category {
            pill(category, color: Palette.ink2)
        }
        // Verdikt a reviewer jsou **jeden** `Text`, ne dva: v úzkém okně se pak ořeže jako celek
        // („CONFIRMED · code-rev…“) místo toho, aby se každý zkracoval na svém konci.
        Text(verbatim: "\(finding.verdict?.rawValue ?? "?") · \(finding.reviewer)")
            .font(.caption2)
            .foregroundStyle(Palette.ink3)
            .lineLimit(1)
    }

    /// Jeden řádek: proč neplatí, čeho se to týkalo a jak to vzít zpátky.
    ///
    /// Text nálezu zůstává (na jeden řádek), protože bez něj by se nedalo poznat, co jsem
    /// odmítl — a pak by se to nedalo ani zkontrolovat.
    private func dismissed(_ finding: Finding, _ dismissal: FindingDismissal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "slash.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                pill(dismissal.reason.label, color: Palette.ink2)
                Text(verbatim: finding.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let actions {
                    // `Vrátit` zůstává na **konci svého řádku** (#283), ačkoli řada akcí
                    // u platného nálezu se vlevo srovnala. Není to tentýž footer: odmítnutý
                    // nález je jeden řádek se zkráceným textem, takže `Spacer` je to místo, do
                    // kterého se text ořezává — a jediná akce na řádku se nemá o co srovnávat.
                    Button("Vrátit") { actions.restore(finding) }
                        .buttonStyle(.mini)
                        .help("Vrátit nález mezi platné")
                }
            }
            // Kdy jsem to posoudil, patří do nápovědy — u PR, ke kterému se vracím za dva
            // dny, je to rozdíl mezi „to jsem řešil“ a „to jsem řešil kdysi“. Bez toho by
            // `dismissedAt` byl stav, který se drží a nikdo ho nečte.
            .help(hint(for: dismissal))
            // Odmítnutí nesahá na rozdělané review, takže se to musí říct: bez téhle věty
            // vypadá review vyčištěné a převzatý komentář v něm odejde.
            if draft.isAdopted(finding) {
                Text("Text je pořád v mém review — vyjmout se dá v tabu Moje review.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Důvod a kdy jsem ho vybral. Datum se skládá do `String`u, ne interpoluje do `Text`u —
    /// v nápovědě je to jedna věta, ne dvě hodnoty pod sebou.
    private func hint(for dismissal: FindingDismissal) -> String {
        let when = dismissal.dismissedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(dismissal.reason.explanation) Odmítnuto \(when)."
    }

    /// Co se s nálezem dá udělat: **jedna řada malých tlačítek vlevo pod textem**, jak to má návrh
    /// (`.inline-find footer`) — hlavní akce plná, odmítnutí obtažená.
    ///
    /// **Do #283 byly akce na dvou stranách** (`Spacer` mezi převzetím a odmítnutím) s odůvodněním,
    /// že kliknout omylem na odmítnutí by znamenalo zahodit nález, o kterém jsem chtěl napsat
    /// komentář. #283 to rozhodnutí otočil a důvody jsou ve specifikaci: vzdálenost nechrání
    /// (v úzkém okně `Spacer` splaskne na svých 8 bodů, takže ochrana byla funkcí šířky okna),
    /// omyl je vratný na místě (odmítnutí nález nesundá, #113, a `Vrátit` je u něj hned) a cena
    /// byla, že odmítnutí sedělo u pravé hrany okna, metr od nálezu, ke kterému patří. Odlišuje
    /// je proto **plocha** — plné akcentové tlačítko proti obtaženým.
    ///
    /// **Bez akcí se nekreslí vůbec**, ani jako mezera. Bublina ke čtení (náhledy, testy skládání
    /// řádků, `canCompose == false`, dokud nevíme proti kterému commitu) by jinak měla pod textem
    /// devět bodů prázdna, které nic neznamenají — a to je horší než těsný text, protože to vypadá
    /// jako chybějící obsah.
    @ViewBuilder private func footer(of finding: Finding) -> some View {
        // **Když se řada nevejde, zlomí se** — nejdřív na dvě řady, a když ani to nestačí, do
        // sloupce. Návrh zalomení nemá (`display: flex` bez `wrap`), ale nemá ani odpověď na
        // šířku, ve které jedna řada nemůže existovat: změřeno renderem, že v úzkém panelu zbývá
        // na řadu 128 bodů a ze tří tlačítek jsou nečitelné pahýly o jednom znaku.
        //
        // `ViewThatFits` staví **všechny** varianty, tedy trojnásobek layoutu na footer (#220).
        // U tří tlačítek je to zanedbatelné a bublina není na každém řádku diffu — na rozdíl od
        // kódu, kde by se to počítat nesmělo.
        let gap = MiniButtonStyle.Metrics.spacing
        // Cíl a „už je v draftu“ se počítají **jednou za footer**, ne uvnitř tlačítka. Obojí hledá
        // řádek v hunkách (`isAdopted` si `draftTarget` počítá samo), takže u velkého souboru je to
        // průchod — a uvnitř by ho `ViewThatFits` vyvolal na každou variantu znovu.
        // `target == nil` = do draftu se psát nedá, akce se pak nenabízí.
        let target = draft.canCompose ? draft.target(finding) : nil
        let isAdopted = target != nil && draft.isAdopted(finding)
        // Prázdný footer se nekreslí — jinak by z něj zbyla jen mezera, viz dokumentace metody.
        if target != nil || actions != nil {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    // Jak to má návrh.
                    HStack(spacing: gap) {
                        adoption(of: finding, to: target, isAdopted: isAdopted)
                        dismissal(of: finding)
                    }
                    // Převzetí a odmítnutí každé na svém řádku.
                    VStack(alignment: .leading, spacing: gap) {
                        HStack(spacing: gap) {
                            adoption(of: finding, to: target, isAdopted: isAdopted)
                        }
                        HStack(spacing: gap) { dismissal(of: finding) }
                    }
                    // A když nevyjde ani to, každé tlačítko samo. Popisek, ze kterého zbylo
                    // `Nepa…`, neříká nic — sloupec je ošklivější, ale čitelný.
                    VStack(alignment: .leading, spacing: gap) {
                        adoption(of: finding, to: target, isAdopted: isAdopted)
                        dismissal(of: finding)
                    }
                }
                // Proč to nejde jako komentář u řádku, musí být vidět **bez** najetí myší: tlačítko
                // s jiným cílem, které vypadá stejně, je horší než delší text. U převzatého nálezu
                // ne — tam už to říká odznak (`v těle mého review`) a byla by to tatáž věta dvakrát.
                //
                // **Na vlastním řádku pod řadou** (#283), ne jako ocas za tlačítkem: je to nejdelší
                // prvek řady, takže by o zalomení celé řady rozhodovala věta, ne tlačítka — změřeno
                // renderem, kde kvůli ní řada padala do sloupce i na širokém okně.
                if case .body = target, !isAdopted {
                    Text(verbatim: "GitHub tady řádkový komentář nepřijme")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            // Návrh má mezi textem nálezu a řadou tlačítek 9 bodů (`.txt` má padding-bottom 9,
            // `footer` padding-top 0). `VStack` uvnitř nálezu drží 4, takže zbylých 5 si bere řada.
            .padding(.top, 5)
        }
    }

    /// Dva důvody vedle sebe, ne rozbalovací menu: je to jedno kliknutí místo dvou a rozdíl
    /// mezi nimi vysvětlí nápověda.
    ///
    /// **Bez uvozujícího `Odmítnout:`** (#283). Návrh ho nemá a nepotřebuje: každý důvod má
    /// vlastní plochu a popisek, který obstojí sám (`actionLabel`) — uvozující slovo bylo to
    /// jediné, co ze dvou modrých textů dělalo akci.
    @ViewBuilder private func dismissal(of finding: Finding) -> some View {
        if let actions {
            ForEach(FindingDismissal.Reason.allCases, id: \.self) { reason in
                Button(reason.actionLabel) { actions.dismiss(finding, reason) }
                    .buttonStyle(.mini)
                    .help(reason.explanation)
            }
        }
    }

    /// Převzetí nálezu do mého review — hlavní pracovní smyčka: nález → komentář mými slovy.
    ///
    /// Když už převzatý je, místo tlačítka je odznak. Bez něj by se nález dal převzít
    /// podruhé, aniž by bylo poznat, že v draftu už jednou je.
    ///
    /// Odmítnutému nálezu se nenabízí vůbec — ta větev se do sbaleného řádku nedostane.
    ///
    /// `target == nil` znamená, že se do draftu psát nedá. Cíl i `isAdopted` počítá `footer(of:)` —
    /// obojí je průchod hunkami a má se udělat jednou za bublinu, ne jednou za variantu rozvržení.
    @ViewBuilder private func adoption(
        of finding: Finding,
        to target: DraftTarget?,
        isAdopted: Bool
    ) -> some View {
        if let target {
            if isAdopted {
                Label(adoptedLabel(for: target), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else {
                Button(adoptLabel(for: target)) { draft.adopt(finding) }
                    .buttonStyle(.miniPrimary)
                    .help(adoptHint(for: target))
            }
        }
    }

    private func adoptLabel(for target: DraftTarget) -> String {
        switch target {
        case .line: "Převzít do review"
        case .body: "Převzít do těla review"
        }
    }

    private func adoptedLabel(for target: DraftTarget) -> String {
        switch target {
        case .line: "v mém review"
        case .body: "v těle mého review"
        }
    }

    private func adoptHint(for target: DraftTarget) -> String {
        switch target {
        case .line:
            "Vloží text nálezu jako můj komentář k tomuhle řádku. Text jde přepsat."
        case .body(let path, _):
            path == nil
                ? "Nález se neváže k místu v kódu, takže půjde do těla review jako text."
                : "Řádek není v diffu, takže GitHub komentář k němu nepřijme. Půjde do těla review jako odkaz na kód, který GitHub vyrenderuje jako úryvek."
        }
    }

    /// Shoda patří **bublině**, ne jednotlivému nálezu — u každého zvlášť by odznak
    /// tvrdil, že si přikyvuje sám se sebou. Odznak `2×` nese značka nad obsahem, takže tady
    /// zbývá jen věta, kdo se shodl.
    private var agreementNote: some View {
        HStack(spacing: 6) {
            Text(verbatim: "Nezávisle nahlásili \(reviewers).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// Odznak. **Ořezává se poslední**: je to jedno slovo, které buď je čitelné, nebo nemá
    /// smysl — `mi…` místo `mimo diff` neřekne nic. V úzkém okně proto ustupují texty vedle něj
    /// (verdikt, reviewer, náhled), ne on.
    private func pill(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
            .layoutPriority(2)
    }

    /// Barva hrany: blokující červená, platný nález `find`, odmítnutý tlumený. **Tatáž škála
    /// jako u karty v panelu** (#175) a u řádku fronty (#172), aby tři místa neříkala o téže
    /// věci každé něco jiného.
    ///
    /// Proužek má bublina **vždycky**, ne jen když blokuje: je to zároveň to, co ze sbalené
    /// značky dělá značku na hraně řádku, a ne jen další pruh v diffu.
    private var accent: Color {
        if state == .dismissed { return Palette.ink3 }
        return isBlocking ? Palette.crit : Palette.find
    }

    /// Obrys. U blokujícího je `color-mix(crit 35 %, line)` z návrhu — vyčíslený v paletě, ne
    /// průhledná červená: skrz krytí by prosvítalo pozadí, na kterém bublina leží, takže by se
    /// obrys měnil podle toho, jestli je pod ním kód, nebo panel.
    private var border: Color {
        isBlocking ? Palette.critLine : Palette.line
    }

    /// Červený pruh a obrys se řídí **platnými** nálezy: bublina, jejíž jediný blokující
    /// nález jsem odmítl, nemá dál křičet, že se na ni má koukat dřív.
    private var isBlocking: Bool {
        group.activeFindings.contains { Policy.isBlocking($0, categories: blockingCategories) }
    }

    /// Jen ti, jejichž nález pořád platí — jinak by odznak `2×` vyjmenoval revieweera, jehož
    /// nález jsem odmítl, a shoda by se počítala z něčeho jiného, než je napsané.
    private var reviewers: String {
        Set(group.activeFindings.map(\.reviewer)).sorted().joined(separator: ", ")
    }
}
