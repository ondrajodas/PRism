import SwiftUI

/// Tab `Nálezy` (#242): souhrn nad tabulkou a tabulka pod ním.
///
/// **Nálezy zůstávají i v panelu vpravo** jako karty (#175) — tab na ně není přesun, ale druhý
/// pohled: panel odpovídá na „co je u tohohle kódu“, tab na „co všechno se na tomhle PR našlo“.
/// Ta druhá otázka je na celou obrazovku, protože se na jeden řádek vejde závažnost, shrnutí,
/// místo, reviewer i akce — a s nimi se vrací řazení podle sloupců, které #175 kvůli 300 bodům
/// zahodil.
struct FindingsTabView: View {
    /// `nil` = žádný uložený záznam. Rozhoduje o tom, proč je tabulka prázdná.
    let record: ReviewRecord?
    /// Ke kterému PR tab patří — podle něj tabulka zapomíná, co bylo rozbalené.
    let pullRequest: PRIdentifier
    /// Nálezy po filtru reviewerů, tedy to, co má být vidět.
    var findings: [Finding] = []
    var dismissals: [FindingKey: FindingDismissal] = [:]
    var blockingCategories: Set<String> = Policy.defaultBlockingCategories
    var isRunning = false
    /// Zahodí uložené nálezy. `nil` = není co zahodit, tlačítko se nekreslí.
    var clear: (() async throws -> Void)?
    var findingActions: FindingActions?
    var draft = FileDraftActions()
    var current: FindingPlace?
    let jump: (Finding) -> Void

    /// Podle čeho je tabulka setříděná. `nil` = pořadí z `Policy.sorted`, tedy podle závažnosti.
    ///
    /// `@State`, protože je to **předvolba pohledu**: smí přetéct mezi pull requesty, protože
    /// „řadím podle místa“ znamená všude totéž — tatáž úvaha jako u filtru reviewerů.
    @State private var sort: FindingTableSort?
    @State private var isConfirmingClear = false
    @State private var isClearing = false
    @State private var clearFailure: String?

    /// Šířka, kterou tab dostal (#220). `nil` znamená, že ji nikdo nezměřil — pak se sází, jako by
    /// bylo místa dost; je to případ náhledů a testů, ne okna.
    @Environment(\.availableWidth) private var availableWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryBar
            if let reason = emptyReason {
                FindingsEmptyView(reason: reason)
            } else {
                FindingsTableView(
                    rows: rows,
                    layout: layout,
                    pullRequest: pullRequest,
                    sort: $sort,
                    blockingCategories: blockingCategories,
                    current: current,
                    findingActions: findingActions,
                    draft: draft,
                    jump: jump
                )
            }
        }
        // `presenting:` podá text nepovinný, takže v těle není `?? ""` — default, který se nikdy
        // nepoužije, čte příště jako možnost prázdné hlášky.
        .alert(
            "Nálezy se nepodařilo zahodit",
            isPresented: .init(get: { clearFailure != nil }, set: { if !$0 { clearFailure = nil } }),
            presenting: clearFailure
        ) { _ in
            Button("Zavřít", role: .cancel) { clearFailure = nil }
        } message: { detail in
            Text(verbatim: detail)
        }
    }

    // MARK: - Souhrn

    /// Řádek nad tabulkou (`.fbar`): kolik je nálezů a co s nimi jde udělat hromadně.
    ///
    /// **Chipy reviewerů v něm nejsou**, i když je návrh kreslí: v aplikaci stojí v hlavičce PR
    /// (#218) a filtrují právě to, co je v téhle tabulce — druhá řada týchž chipů by byla dvě
    /// místa pro jedno nastavení. Tatáž úvaha, kvůli které #219 vyhodil souhrn `+X −Y` z lišty
    /// nad diffem.
    ///
    /// **A není v něm ani `jen blokující`**, které návrh v tomhle pruhu má: zúžení na blokující je
    /// od #187 režim **procházení** v liště nad diffem, a jako filtr řádků by rozešel odznak na
    /// záložce s tím, co je v tabulce vidět — tedy přesně to, co má být na jeden zdroj.
    private var summaryBar: some View {
        HStack(spacing: 9) {
            Text(verbatim: summaryText)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink2)
                .lineLimit(1)
            Spacer(minLength: 9)
            if let finishedAt = record?.finishedAt {
                Text(finishedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                    .help("Kdy review doběhlo")
            }
            clearButton
        }
        .padding(.horizontal, FindingTableLayout.inset)
        .padding(.vertical, 9)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    /// Souhrn počtů. Mluví o **nálezech**, ne o řádcích tabulky: řádek je místo, takže shoda dvou
    /// reviewerů je jeden řádek a dva nálezy — a odznak na záložce počítá totéž co tahle věta.
    private var summaryText: String {
        let tally = self.tally
        guard !tally.isEmpty else { return "Žádné nálezy" }
        var parts = [Plural.czech(tally.total, one: "nález", few: "nálezy", many: "nálezů")]
        if tally.blocking > 0 {
            parts.append(Plural.czech(
                tally.blocking,
                one: "blokující",
                few: "blokující",
                many: "blokujících"
            ))
        }
        if tally.dismissed > 0 {
            parts.append(Plural.czech(
                tally.dismissed,
                one: "odmítnutý",
                few: "odmítnuté",
                many: "odmítnutých"
            ))
        }
        if rows.count != tally.total {
            parts.append(Plural.czech(rows.count, one: "místo", few: "místa", many: "míst"))
        }
        return parts.joined(separator: " · ")
    }

    /// Zahození uložených nálezů — přestěhované z panelu (#242), kde do #242 bydlelo.
    ///
    /// **Ochrana proti mazání mimo cache se nepíše znovu**: maže `ReviewStore`, který ji má u sebe.
    /// Za běhu je tlačítko zakázané — doběhlý skill by se zapsal do právě vyčištěného záznamu.
    @ViewBuilder private var clearButton: some View {
        if let clear {
            Button("Zahodit nálezy", systemImage: "trash") {
                isConfirmingClear = true
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .disabled(isRunning || isClearing)
            .help(isRunning
                ? "Nejdřív nech review doběhnout, nebo ho zruš"
                : "Zahodit uložené nálezy tohohle commitu a pustit review znovu")
            // Potvrzení schválně: vrátit se k nálezům jde jedině novým během, a ten stojí session.
            // Není to nevratné zdánlivě, je to nevratné doopravdy.
            .confirmationDialog(
                "Zahodit uložené nálezy?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Zahodit", role: .destructive) { runClear(clear) }
                Button("Zpět", role: .cancel) {}
            } message: {
                Text("Zpátky je dostaneš jedině novým review, které stojí session. Historie starších commitů zůstane.")
            }
        }
    }

    private func runClear(_ clear: @escaping () async throws -> Void) {
        isClearing = true
        Task {
            defer { isClearing = false }
            do {
                try await clear()
            } catch {
                // Nesmazaný záznam se nesmí tvářit jako smazaný — vrátil by se po restartu
                // a nikdo by nevěděl proč.
                clearFailure = error.localizedDescription
            }
        }
    }

    // MARK: - Data

    private var tally: FindingsTally {
        Policy.tally(of: findings, dismissals: dismissals, categories: blockingCategories)
    }

    private var rows: [FindingTableRow] {
        FindingTableRow.rows(
            of: findings,
            sort: sort,
            blocking: blockingCategories,
            dismissals: dismissals
        )
    }

    private var layout: FindingTableLayout {
        Policy.findingTableLayout(availableWidth: availableWidth ?? 1000)
    }

    private var emptyReason: FindingsEmptyReason? {
        Policy.findingsEmptyReason(
            visible: findings,
            record: record,
            isRunning: isRunning,
            categories: blockingCategories
        )
    }
}

/// Proč není v tabulce nic — větou, ne prázdnou plochou.
///
/// **Prázdná obrazovka se čte jako „čisto“**, a to je ta nejdražší záměna, jakou tohle okno umí.
/// V tabu přes celé okno je ta věta potřebnější než v panelu, ne méně.
struct FindingsEmptyView: View {
    let reason: FindingsEmptyReason

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.callout)
                .foregroundStyle(isFailure ? Palette.crit : Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                // Mono a k vybrání, jako u ostatních chybových stavů v okně: text od `claude` nebo
                // od `gitu` je to jediné, z čeho se pozná, co dělat dál, a lepí se z něj vyhledávání.
                Text(verbatim: detail)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var isFailure: Bool {
        switch reason {
        case .failed, .checkoutFailed: true
        default: false
        }
    }

    private var title: String {
        switch reason {
        case .hiddenByReviewerFilter: "Nálezy jsou schované filtrem reviewerů."
        case .clean: "Review doběhlo a nic nenašlo."
        case .failed: "Reviewer spadl, takže nálezy nejsou — a to není totéž jako čisto."
        case .checkoutFailed: "Pracovní kopii se nepodařilo připravit, takže reviewer neběžel."
        case .running: "Review běží. Co se právě děje, je v tabu Průběh."
        case .nothingRan: "Nálezy k tomuhle běhu nejsou."
        }
    }

    /// Text od `claude` nebo od `gitu` je to jediné, z čeho se pozná, co dělat dál — proto celý
    /// a k vybrání, ne shrnutý do věty výš.
    private var detail: String? {
        switch reason {
        case .failed(let detail), .checkoutFailed(let detail): detail
        default: nil
        }
    }
}
