import SwiftUI

/// Labely a vyžádaní reviewery v pravém panelu (#392) — dvě sekce pod hlavičkou, **nad segmenty**.
///
/// **Nad segmenty, ne jako třetí segment.** Segment se přepíná, kdežto tyhle dvě sekce platí pro
/// celý pull request a mají být vidět **spolu** s nálezy: „kdo to má taky na stole“ je otázka,
/// kterou si člověk klade zrovna při čtení nálezu. Pod segmenty by se zase čtly jako obsah toho
/// aktivního.
///
/// **Ne v hlavičce PR**, a to je změřené (#390): pruh souřadnic je `HStack`, který nezalamuje,
/// takže by se s labely i reviewery ořezal — cizí PR potřebuje 1056 bodů proti ~1000, které na
/// výchozím okně zbývají. Panel je sloupec, takže mu zalomení nevadí.
///
/// **Sekce, která nemá co ukázat, se nekreslí** — jinak by panel u každého takového PR platil
/// nadpisem za prázdno. Na vlastním PR zůstane samotné `+ label`: tam je to jediná cesta, jak
/// první label přidat.
struct PanelMetadataView: View {
    /// `nil` = ještě se nenačetlo. Prázdný snímek je platná odpověď, `nil` není.
    let state: MetadataState?
    let editing: Policy.MetadataEditing
    /// Do kterého repozitáře se nový label založí (#413). Kreslí to potvrzení v nabídce, ne panel —
    /// ale panel je jediné místo, které tu hodnotu má odkud vzít.
    let repo: RepoID
    /// Šířka, kterou má panel na obsah — **spočítaná, ne vyjednaná** (pravidlo #220). Zalomení
    /// chipů z ní počítá `Policy`.
    let contentWidth: Double
    var known: [PullRequestLabel] = []
    var candidates: [ReviewerCandidate] = []
    /// Proč je nabídka labelů prázdná (`nil` = načetla se). Kreslí to popover, ne panel.
    var labelPickerFailure: String?
    var reviewerPickerFailure: String?
    /// Dorazily už nabídky? Prázdná **načtená** nabídka je odpověď o repu, nenačtená není.
    var hasLoadedLabels = false
    var hasLoadedCandidates = false
    var actionState: MetadataActionState?
    var actions = MetadataActions()

    @State private var isPickingLabel = false
    @State private var isPickingReviewer = false

    /// Odsazení bloku z návrhu (`padding: 11px 13px`) a mezera mezi sekcemi (`gap: 11px`).
    ///
    /// **Vodorovné odsazení je `internal`, protože ho potřebuje i volající**: `ReviewPanel` z něj
    /// počítá šířku, která na chipy zbývá. Dvě konstanty by znamenaly dvě pravdy o jedné šířce —
    /// a zalomení by se rozešlo se sazbou při prvním doladění (pravidlo #236).

    static let insetHorizontal = 13.0
    private static let insetVertical = 11.0
    private static let sectionSpacing = 11.0

    /// Šířka, která v bloku zbývá na chipy, pro panel dané šířky.
    static func contentWidth(inPanelOf width: Double) -> Double { width - 2 * insetHorizontal }

    var body: some View {
        // Celý blok se nekreslí, když v něm není ani jedna sekce — jinak by po sobě zůstala
        // vodorovná linka bez obsahu.
        if hasAnything {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                if let reason = state?.failure {
                    failure(reason)
                } else {
                    if showsLabels { labels }
                    if showsReviewers { reviewers }
                }
                if let reason = editing.reason { blocked(reason) }
                if actionState?.showsNotice == true { notice }
            }
            .padding(.horizontal, Self.insetHorizontal)
            .padding(.vertical, Self.insetVertical)
            .frame(width: contentWidth + 2 * Self.insetHorizontal, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        }
    }

    // MARK: - Sekce

    private var labels: some View {
        PanelSection(caption: "Labely") {
            VStack(alignment: .leading, spacing: LabelChipStyle.spacing) {
                // Řádky jsou z `Policy`, ne z pružného rozvržení: dvouřádkový strop a `+N` se
                // z „nech to zalomit“ vyjádřit nedají.
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { row in
                    HStack(spacing: LabelChipStyle.spacing) {
                        ForEach(Array(row.element.enumerated()), id: \.offset) { chip in
                            self.chip(chip.element)
                        }
                    }
                }
            }
        }
    }

    private var reviewers: some View {
        PanelSection(caption: "Reviewery") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(metadata.reviewers, id: \.login) { reviewer in
                    reviewerRow(reviewer)
                }
                // **Týmy pod lidmi.** Odpověď je to, kvůli čemu se na sekci kouká, a tu nese jedině
                // člověk; tým říká jen „leží to na skupině“.
                ForEach(metadata.teams, id: \.self) { team in
                    teamRow(team)
                }
                if editing.isVisible { reviewerAction }
            }
        }
    }

    /// Řádek reviewera: iniciála, jméno a **odpověď**.
    ///
    /// Když se panel zúží, ustoupí **jméno** (ořeže se), odpověď zůstává celá: kvůli odpovědi se na
    /// sekci kouká. Drží to `fixedSize` na odpovědi — bez něj by SwiftUI zkrátil oba texty.
    private func reviewerRow(_ reviewer: RequestedReviewer) -> some View {
        HStack(spacing: 7) {
            ReviewerAvatarView(login: reviewer.login, answer: reviewer.answer)
            Text(verbatim: reviewer.login)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(reviewer.login)
            Spacer(minLength: 4)
            Text(verbatim: reviewer.answer.czechLabel)
                .font(.system(size: 11))
                .foregroundStyle(answerColor(reviewer.answer))
                .fixedSize()
        }
    }

    /// Řádek vyžádaného **týmu** (#392).
    ///
    /// **Bez avatara a bez odpovědi**, a obojí je rozhodnutí: kolečko s iniciálou znamená v tomhle
    /// okně osobu, a `schválil`/`chce změny`/`čeká` u týmu nemá význam — odpověď dá až ten, kdo za
    /// tým odpoví, a ten se objeví jako **osoba** v řádku výš. Místo iniciály je proto skupinová
    /// ikona ve **čtverci** (jiný tvar = jiný druh věci) a v pravém sloupci stojí `tým`: prázdný
    /// sloupec by vypadal jako chybějící data, kdežto tohle je jediné pravdivé slovo, které tam
    /// patří.
    private func teamRow(_ slug: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.ink3)
                .frame(width: 16, height: 16)
                .background(Palette.raised, in: .rect(cornerRadius: 4))
                .overlay {
                    // Přerušovaně, jako u `čeká` a u `+`: přerušované se ještě nestalo.
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            Text(verbatim: slug)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(slug)
            Spacer(minLength: 4)
            Text("tým")
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink3)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("vyžádaný tým \(slug)")
    }

    @ViewBuilder private var reviewerAction: some View {
        if editing.isAllowed {
            Button {
                isPickingReviewer = true
            } label: {
                AddChipLabel(title: Self.addReviewerTitle)
            }
            .buttonStyle(.plain)
            .disabled(actionState?.isBusy == true)
            .popover(isPresented: $isPickingReviewer, arrowEdge: .bottom) {
                ReviewerPickerView(
                    candidates: candidates,
                    isLoaded: hasLoadedCandidates,
                    failure: reviewerPickerFailure,
                    request: { candidate in
                        isPickingReviewer = false
                        actions.request(candidate)
                    },
                    load: actions.loadCandidates
                )
            }
        } else {
            // Ztlumené **s důvodem**: „tady se to dělá, jen teď ne“ je u vypnutého odesílání pravda,
            // takže chybějící tlačítko by vypadalo jako rozbitá aplikace. Na cizím PR se sem
            // nedostaneme vůbec (`editing == .absent`) — tam se to nedělá nikdy.
            AddChipLabel(title: Self.addReviewerTitle, isEnabled: false)
                .help(editing.reason ?? "")
        }
    }

    @ViewBuilder private func chip(_ chip: Policy.LabelChip) -> some View {
        switch chip {
        case .label(let label, let maxWidth):
            LabelChipView(label: label, maxWidth: maxWidth)
        case .more(let count):
            LabelMoreChipView(count: count)
        case .add:
            addLabelAction
        }
    }

    @ViewBuilder private var addLabelAction: some View {
        if editing.isAllowed, hasSnapshot {
            Button {
                isPickingLabel = true
            } label: {
                AddChipLabel(title: Self.addLabelTitle)
            }
            .buttonStyle(.plain)
            .disabled(actionState?.isBusy == true)
            .popover(isPresented: $isPickingLabel, arrowEdge: .bottom) {
                LabelPickerView(
                    repo: repo,
                    known: known,
                    selected: metadata.labels,
                    isLoaded: hasLoadedLabels,
                    failure: labelPickerFailure,
                    editing: editing,
                    // Popover se **nezavírá**: label je přepínač a přidat dva za sebou je běžné.
                    toggle: actions.toggle,
                    // Zavírá se **taky ne** (#413): založený label se hned objeví v seznamu jako
                    // zaškrtnutý, takže zavřený popover by schoval zrovna tu odpověď na to, jak to
                    // dopadlo.
                    create: actions.create,
                    load: actions.loadLabels
                )
            }
        } else {
            // **Dokud snímek nedorazil, je akce zakázaná.** Sada se posílá celá, takže bez ní by
            // klik neudělal nic — a tlačítko, po kterém se nic nestane, je horší než zakázané.
            AddChipLabel(title: Self.addLabelTitle, isEnabled: false)
                .help(editing.reason ?? (hasSnapshot ? "" : "Labely se ještě načítají."))
        }
    }

    /// Načtení selhalo. **Vlastní stav, ne prázdné sekce**: „PR nemá labely“ a „labely jsem
    /// nezjistil“ se nesmí slít — podle prvního se sekce nekreslí, podle druhého se nesmí dát měnit
    /// sada, kterou aplikace nezná (proto se v tomhle stavu akce nekreslí vůbec).
    private func failure(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.stale)
            Text("Labely a reviewery se nepodařilo načíst. \(reason)")
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    /// Proč jsou akce zakázané — **napsané, ne jen v tooltipu** (nález z proklikání).
    ///
    /// Zašedlé tlačítko bez důvodu je otázka, na kterou okno neodpovídá: člověk vidí, že to nejde,
    /// a jde hledat do nastavení, co si vypnul. Věta je tatáž, na které skončí publisher, takže se
    /// okno neptá dvakrát jinak. **Není to výstraha** — vypnutá brána je nastavení, ne porucha, tak
    /// je i tiše šedá.
    private func blocked(_ reason: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "lock")
                .foregroundStyle(Palette.ink3)
            Text(verbatim: reason)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }

    /// Proč akce nedopadla. Drží se, dokud ji člověk nezavře — chyba, která zmizí sama, je chyba,
    /// kterou nikdo nepřečte.
    ///
    /// **Dvě různé věty, ne jedna** (#413). `failed` mluví o **jedné** akci, která nedopadla;
    /// `createdNotAdded` znamená, že je jistě hotová **půlka**, a to je stav, který u zakládání labelu
    /// existovat **musí** — dvě volání se spojit nedají. Slít je do jedné hlášky by bylo přesně to,
    /// čemu se má vyhnout: text v UI, který tvrdí něco jiného, než co data unesou.
    @ViewBuilder private var notice: some View {
        switch actionState {
        case .createdNotAdded(let name, let error):
            noticeRow(tint: Palette.crit) {
                VStack(alignment: .leading, spacing: 3) {
                    (
                        Text("Label ") + Text(verbatim: name).bold()
                            + Text(" se v repozitáři založil, na PR se ho přidat nepovedlo. Je v nabídce — přidáš ho kliknutím.")
                    )
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    // **Proč to spadlo, se nezahazuje.** Zákres kreslí jen tu první větu, ale je to
                    // jediné selhání v tomhle panelu, které by jinak neřeklo důvod — a další krok
                    // se od důvodu odvozuje (jiná věta u nepřihlášeného `gh` než u zavřeného PR).
                    Text(verbatim: error.userDescription)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .failed(let error):
            noticeRow(tint: Palette.crit) {
                Text(verbatim: error.userDescription)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .settingLabels, .requestingReviewer, .creatingLabel, nil:
            EmptyView()
        }
    }

    private func noticeRow(tint: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(tint)
            content()
            // `.mini`, ne systémové tlačítko: zákres ho kreslí jako `<span class="mini">` a systémový
            // tvar byl v 300bodovém panelu skoro tak vysoký jako celá věta. `fixedSize` drží
            // `flex: none` z návrhu — ustupovat má text, ne akce.
            Button("Zavřít", action: actions.clearFailure)
                .buttonStyle(.mini)
                .fixedSize()
        }
        .font(.caption)
    }

    // MARK: - Data

    private static let addLabelTitle = "+ label"
    private static let addReviewerTitle = "+ reviewer"

    private var metadata: PullRequestMetadata { state?.metadata ?? PullRequestMetadata() }

    private var layout: Policy.LabelChipLayout {
        Policy.labelChips(
            metadata.labels,
            width: contentWidth,
            metrics: LabelChipStyle.metrics(addTitle: Self.addLabelTitle),
            canAdd: editing.isVisible
        )
    }

    /// Dorazil snímek labelů? Bez něj se sada nemá odkud skládat.
    private var hasSnapshot: Bool { state?.metadata != nil }

    private var showsLabels: Bool { !metadata.labels.isEmpty || editing.isVisible }

    private var showsReviewers: Bool {
        !metadata.reviewers.isEmpty || !metadata.teams.isEmpty || editing.isVisible
    }

    /// Je v bloku vůbec co nakreslit? `nil` stav (ještě se nenačetlo) nedá ani jednu sekci — a na
    /// cizím PR bez labelů a reviewerů taky ne.
    private var hasAnything: Bool {
        state?.failure != nil || showsLabels || showsReviewers || actionState?.showsNotice == true
    }

    private func answerColor(_ answer: ReviewerAnswer) -> Color {
        switch answer {
        case .approved: Palette.ok
        case .changesRequested: Palette.crit
        case .waiting: Palette.ink3
        }
    }
}

/// Kolečko s iniciálou u reviewera (#392) — **tři stavy odpovědi**.
///
/// Vlastní view vedle `AvatarView`, ne jeho varianta: `AvatarView` kreslí obrázek z GitHubu, kdežto
/// `reviewRequests` obrázek nedává vůbec (jen login), takže by tady loader jen mlčel. A hlavně:
/// tady nese kolečko **odpověď** (zelené, červené, přerušované), což u autora události nedává smysl.
/// Iniciály se počítají tou samou funkcí, aby se `ErikZigo` nesázelo dvakrát jinak.
struct ReviewerAvatarView: View {
    let login: String
    let answer: ReviewerAnswer

    /// `.av.sm` z návrhu — šestnáct bodů, mono 8, `border-box`.
    private static let size = 16.0

    var body: some View {
        Circle()
            .fill(background)
            .frame(width: Self.size, height: Self.size)
            .overlay { border }
            .overlay {
                Text(verbatim: initials)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(foreground)
            }
            .accessibilityLabel("\(login) — \(answer.czechLabel)")
    }

    /// Přerušovaný okraj u `čeká` je tatáž úmluva jako u `+`: **přerušované se ještě nestalo.**
    @ViewBuilder private var border: some View {
        switch answer {
        case .approved, .changesRequested: EmptyView()
        case .waiting: Circle().strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }

    private var background: Color {
        switch answer {
        case .approved: Palette.ok.opacity(0.15)
        case .changesRequested: Palette.crit.opacity(0.15)
        case .waiting: Palette.raised
        }
    }

    private var foreground: Color {
        switch answer {
        case .approved: Palette.ok
        case .changesRequested: Palette.crit
        case .waiting: Palette.ink2
        }
    }

    private var initials: String {
        let words = AvatarView.words(in: login)
        guard let first = words.first else { return "?" }
        if let second = words.dropFirst().first, let a = first.first, let b = second.first {
            return "\(a)\(b)".uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }
}
