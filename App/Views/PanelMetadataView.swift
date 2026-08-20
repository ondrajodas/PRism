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
    /// Šířka, kterou má panel na obsah — **spočítaná, ne vyjednaná** (pravidlo #220). Zalomení
    /// chipů z ní počítá `Policy`.
    let contentWidth: Double
    var known: [PullRequestLabel] = []
    var candidates: [String] = []
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
                if let error = actionState?.failure { actionFailure(error) }
            }
            .padding(.horizontal, Self.insetHorizontal)
            .padding(.vertical, Self.insetVertical)
            .frame(width: contentWidth + 2 * Self.insetHorizontal, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.lineSoft).frame(height: 1) }
        }
    }

    // MARK: - Sekce

    private var labels: some View {
        section("Labely") {
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
        section("Reviewery") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(metadata.reviewers, id: \.login) { reviewer in
                    reviewerRow(reviewer)
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
                    request: { login in
                        isPickingReviewer = false
                        actions.request(login)
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
        if editing.isAllowed {
            Button {
                isPickingLabel = true
            } label: {
                AddChipLabel(title: Self.addLabelTitle)
            }
            .buttonStyle(.plain)
            .disabled(actionState?.isBusy == true)
            .popover(isPresented: $isPickingLabel, arrowEdge: .bottom) {
                LabelPickerView(
                    known: known,
                    selected: metadata.labels,
                    isLoaded: hasLoadedLabels,
                    failure: labelPickerFailure,
                    // Popover se **nezavírá**: label je přepínač a přidat dva za sebou je běžné.
                    toggle: actions.toggle,
                    load: actions.loadLabels
                )
            }
        } else {
            AddChipLabel(title: Self.addLabelTitle, isEnabled: false)
                .help(editing.reason ?? "")
        }
    }

    private func section(_ caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: caption)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.ink3)
            content()
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

    /// Proč akce nedopadla. Drží se, dokud ji člověk nezavře — chyba, která zmizí sama, je chyba,
    /// kterou nikdo nepřečte.
    private func actionFailure(_ error: PublishError) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.crit)
            Text(verbatim: error.userDescription)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("Zavřít", action: actions.clearFailure)
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

    private var showsLabels: Bool { !metadata.labels.isEmpty || editing.isVisible }

    private var showsReviewers: Bool { !metadata.reviewers.isEmpty || editing.isVisible }

    /// Je v bloku vůbec co nakreslit? `nil` stav (ještě se nenačetlo) nedá ani jednu sekci — a na
    /// cizím PR bez labelů a reviewerů taky ne.
    private var hasAnything: Bool {
        state?.failure != nil || showsLabels || showsReviewers || actionState?.failure != nil
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
