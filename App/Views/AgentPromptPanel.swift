import SwiftUI

/// Tab `Zadání` v panelu vpravo — na vlastním PR místo verdiktu (#333).
///
/// **Verdikt ani `Odeslat` tady nejsou, a nezašedly — zmizely celé.** `APPROVE`
/// i `REQUEST_CHANGES` na vlastní PR GitHub odmítne (422, změřeno u #62), takže zakázané tlačítko
/// by svádělo na něj kliknout a přečíst si chybu. Panel má jednu úlohu a ta se jmenuje v jeho
/// hlavičce: sesbírat, co je potřeba opravit, a udělat z toho jedno zadání pro agenta.
///
/// **Nic se odsud neodesílá.** Tlačítko otevře sheet s celým textem; ten skončí ve schránce nebo
/// v souboru. Proto tu není druhé potvrzení — dvě kliknutí na dvou tlačítkách jsou brána proti
/// odeslání na GitHub a tady se neodesílá nic (stejná úvaha jako u odpovědi do vlákna, #73).
struct AgentPromptPanel: View {
    /// Zadání složené z toho, co aplikace o PR ví. Skládá ho store při každém čtení — panel
    /// z něj kreslí počty i náhled, takže by dvě volání znamenala dvě různá čísla.
    let prompt: AgentPrompt
    /// Stav načtení konverzace. `nil` = ještě se o ni nikdo nepokusil.
    var conversation: ConversationState?
    /// Zapnutí a vypnutí volby.
    var toggle: (AgentPromptChoice) -> Void = { _ in }
    var isEnabled: (AgentPromptChoice) -> Bool = { _ in false }
    /// Otevře sheet s celým textem. **Neodesílá nic.**
    var compose: () -> Void = {}
    /// Rozdělané review, které na vlastním PR zbylo z dřívějška. `nil` = žádné není.
    var leftoverDraft: ReviewDraft?
    var discardDraft: () -> Void = {}
    /// Co zbývá předat (#334) — razítko, novinky od předání, nebo že zadání po pushi zastaralo.
    /// Rozhoduje `Policy.handoff`; panel z toho jen kreslí.
    var report: HandoffReport = .never
    /// Zadání jen z toho, co po předání přibylo v diskuzi (#334). **Otevře sheet, neodesílá nic.**
    var composeFresh: () -> Void = {}
    /// Pustit review znovu po pushi (#334). Samo se nepustí nikdy — automat se vlastních PR
    /// netýká vůbec (#332), takže je z toho tlačítko.
    var runReview: () -> Void = {}
    /// Běží zrovna review? Pak je tlačítko zakázané **s důvodem** — druhé kolo na tentýž commit
    /// jsou peníze za nic.
    var isReviewing = false

    @State private var isConfirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    title
                    // **Věta o nenačtené konverzaci stojí nad razítkem**, ne pod ním: mluví o tom,
                    // z čeho se počítá „co zbývá“, takže se musí čít dřív než tvrzení „nic nového
                    // nepřišlo“. Bez ní by to tvrzení platilo jen o tom, co je zrovna v paměti.
                    conversationNote
                    handoffSection
                    // **Volby a náhled jen tam, kde je z čeho vybírat** (#334). Po předání není
                    // (všechno je předané) a po pushi má panel vlastní podobu — dvě cesty dál,
                    // ne sedm zaškrtávátek nad nálezy, které platí pro starý kód.
                    if report.showsChoices {
                        choices
                        preview
                    }
                    if let leftoverDraft { leftover(leftoverDraft) }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            composer
        }
    }

    // MARK: - Hlavička

    /// Titulek s klávesovou zkratkou, jak ho má návrh v hlavičce panelu (`.side > header`).
    /// Segment nad ním se jmenuje `Zadání`, aby se do 300 bodů vešel vedle `Nálezů`.
    private var title: some View {
        HStack(spacing: 6) {
            Text("Zadání pro agenta")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 4)
            Text(verbatim: "⌘⇧P")
                .font(.system(size: 9.5, design: .monospaced))
                .padding(.horizontal, 4)
                .foregroundStyle(Palette.ink3)
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line) }
        }
    }

    /// Že konverzace **není** načtená, se musí říct.
    ///
    /// `Conversation` se nepersistuje (načítá se při zobrazení PR), takže se zadání skládá z toho,
    /// co je v paměti — a bez téhle věty by prázdný počet vláken vypadal jako „nikdo nic nenapsal“.
    /// Rozlišuje se **načítání od selhání**: čekání samo přejde, chyba ne.
    @ViewBuilder private var conversationNote: some View {
        switch conversation {
        case .loaded:
            EmptyView()
        case .loading, nil:
            note("Konverzaci k PR ještě načítám — vlákna, komentáře a souhrny review v zadání zatím nejsou.", tint: Palette.ink2)
        case .failed(let detail):
            note("Konverzaci k PR se nepovedlo načíst, takže v zadání nejsou vlákna, komentáře ani souhrny review. \(detail)", tint: Palette.crit)
        }
    }

    private func note(_ text: String, tint: Color) -> some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Volby

    /// Zaškrtávací řádky z návrhu (`.radio` se čtvercovým `i`) — sedm, v pořadí výčtu.
    ///
    /// **Vyřešená vlákna a odmítnuté nálezy jsou vidět s počtem, i když jsou vypnuté.** Zmizet
    /// nesmí: `vyřešeno` je stav vlákna na GitHubu, ne důkaz, že je hotovo, a odmítnutý nález je
    /// moje rozhodnutí, které si můžu chtít v zadání připomenout.
    private var choices: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AgentPromptChoice.allCases, id: \.self) { choice in
                choiceRow(choice)
            }
        }
    }

    private func choiceRow(_ choice: AgentPromptChoice) -> some View {
        let on = isEnabled(choice)
        return Button {
            toggle(choice)
        } label: {
            HStack(spacing: 7) {
                checkbox(on: on)
                Text(verbatim: choice.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(on ? Palette.ink : Palette.ink2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let total = prompt.inventory.count(of: choice) {
                    Text(verbatim: Self.choiceCount(selected: prompt.included.count(of: choice) ?? 0, of: total))
                        .font(.system(size: 10.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Self.choiceHelp(choice, selected: prompt.included.count(of: choice), of: prompt.inventory.count(of: choice)))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Počet u volby: `3`, když do textu jde všechno, `1 z 3`, když ne (#377).
    ///
    /// Do #377 tu stál jen počet dostupných položek. Přestalo to být pravdivé ve chvíli, kdy se
    /// vybírá **po položkách**: u volby, ze které jsou v textu dvě položky ze tří, by `3` tvrdilo
    /// o textu něco, co v něm není. Plný počet zůstává tam, kde jde všechno — `3 z 3` je šum.
    nonisolated static func choiceCount(selected: Int, of total: Int) -> String {
        selected == total ? "\(total)" : "\(selected) z \(total)"
    }

    /// Nápověda u volby — a když je část položek vypnutá, i to, kde se to dá přepnout.
    ///
    /// Bez té druhé věty vypadá `1 z 3` jako chyba: v panelu není nic, čím by se s tím dalo hýbat,
    /// protože jednotlivé položky bydlí v sheetu.
    nonisolated static func choiceHelp(_ choice: AgentPromptChoice, selected: Int?, of total: Int?) -> String {
        guard let selected, let total, selected < total else { return choice.explanation }
        return choice.explanation
            + " — část položek je vypnutá; vidět a přepnout se dají v okně se zadáním."
    }

    /// Čtvereček z návrhu: 12 bodů, poloměr 3. Zapnutý má akcentové obtažení **4 body dovnitř**
    /// (`border-width: 4`) na ploše panelu, ne plnou barvu — proto se kreslí obtažením přes plochu.
    private func checkbox(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(on ? Palette.accent : Palette.ink3, lineWidth: on ? 4 : 1)
            }
            .frame(width: 12, height: 12)
    }

    // MARK: - Náhled

    /// Náhled textu, jak ho má návrh (`.pl-sec` + `.pl-mono` s omezenou výškou).
    ///
    /// Ukazuje **začátek toho, co se zkopíruje**, ne parafrázi: kdo mění volby, má rovnou vidět,
    /// co se v textu změnilo. Celý text je v sheetu.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(previewCaption)
            Text(verbatim: prompt.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .lineLimit(9)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Palette.raised, in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line) }
        }
    }

    private var previewCaption: String {
        let items = Plural.czech(
            prompt.included.total,
            one: "položka",
            few: "položky",
            many: "položek"
        )
        return "Náhled · \(items), \(prompt.sizeText)"
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text.uppercased())
            .font(.system(size: 10, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Palette.ink3)
    }

    // MARK: - Předáno není hotovo (#334)

    /// Razítko předání, novinky od něj, nebo varování po pushi — podle toho, co řekla `Policy`.
    ///
    /// **Nepředáno nekreslí nic.** Věta „ještě jsi nic nepředal“ by v panelu, který o předávání
    /// celý je, zabírala řádek a neřekla nic; kdo nic nepředal, vidí volby a tlačítko.
    @ViewBuilder private var handoffSection: some View {
        switch report.stage {
        case .never:
            EmptyView()
        case .delivered:
            if let handoff = report.handoff { delivered(handoff) }
        case .changed, .unverified:
            if let handoff = report.handoff { changed(handoff) }
        case .outdated:
            outdated
        }
    }

    /// Předáno a od té doby nic — razítko a věta, že se nové věci objeví tady.
    private func delivered(_ handoff: Handoff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Předáno")
            stampRow(handoff)
            Text("Nic nového od té doby nepřišlo. Až agent pushne nebo někdo napíše komentář, objeví se to tady.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Předáno, ale něco zbývá — razítko a **kolik** toho je. Volby a tlačítko zůstávají pod tím,
    /// protože zadání se dá sestavit znovu.
    private func changed(_ handoff: Handoff) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Předáno")
            stampRow(handoff)
            Text(verbatim: Self.pendingNotice(report))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pilulka s počtem předaných položek a k ní čas a hlava, proti které se předávalo.
    ///
    /// **Mint, ne akcent** (`.pill.mint` z návrhu): je to konstatování stavu, se kterým se nic
    /// nedělá — tatáž barva jako u odznaku shody a rozdělaného review v řádku.
    private func stampRow(_ handoff: Handoff) -> some View {
        // Zalomená řada, ne `HStack`: v panelu užším než 300 bodů se pilulka a čas vedle sebe
        // nevejdou, a zkrácený čas by zahodil zrovna hlavu, kvůli které tam je.
        FlowRow(spacing: 8, lineSpacing: 4) {
            Text(verbatim: "✓ \(Plural.czech(handoff.count, one: "položka", few: "položky", many: "položek"))")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.mint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Palette.mint.opacity(0.15), in: .capsule)
            Text(verbatim: Self.stampLabel(of: handoff))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Po pushi: varování a k němu dva řádky o tom, co se stalo s materiálem.
    ///
    /// Řádky jsou **konstatování, ne zaškrtávátka** (odchylka od návrhu, který je kreslí jako
    /// `.radio`): v tomhle stavu o složení zadání rozhodují dvě tlačítka pod tím — buď nové review,
    /// nebo jen to, co přibylo v diskuzi. Zaškrtávátko by slibovalo volbu, kterou ani jedno z nich
    /// nenabízí. **Nálezy tím nemizí**: zůstávají v diffu, v tabu `Nálezy` i v segmentu `Nálezy`
    /// vedle, jen se do zadání nepředvybírají — sundat je smí jedině odmítnutí (#113).
    private var outdated: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: Self.outdatedNotice(report))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.stale)
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(Palette.stale.opacity(0.11), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.stale.opacity(0.4)) }
            VStack(alignment: .leading, spacing: 4) {
                staleRow(
                    "Nové v diskuzi",
                    count: report.freshDiscussion.count,
                    tint: report.freshDiscussion.isEmpty ? Palette.ink2 : Palette.ink,
                    countTint: Palette.ink3,
                    // Zaškrtnuté jen tehdy, když je co zaškrtnout: `✓ Nové v diskuzi 0` slibuje
                    // obsah, který v zúženém zadání nebude — a tlačítko pod tím je v tu chvíli
                    // zakázané, takže by si ta dvě místa odporovala.
                    on: !report.freshDiscussion.isEmpty,
                    help: "Vlákna, komentáře pod PR a souhrny review, které po předání přibyly — jen z nich se skládá „Sestavit i tak“"
                )
                staleRow(
                    "Nálezy proti staré hlavě",
                    count: report.staleFindings,
                    tint: Palette.ink2,
                    countTint: Palette.stale,
                    on: false,
                    help: "Platí pro commit, který na PR není. Ze seznamu nemizí, do zadání se ale nepředvybírají — pusť review znovu"
                )
            }
        }
    }

    /// Řádek se čtverečkem, jak ho má návrh u voleb — ale **bez akce**, viz `outdated`.
    private func staleRow(
        _ label: String,
        count: Int,
        tint: Color,
        countTint: Color,
        on: Bool,
        help: String
    ) -> some View {
        HStack(spacing: 7) {
            checkbox(on: on)
            Text(verbatim: label)
                .font(.system(size: 11.5))
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "\(count)")
                .font(.system(size: 10.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(countTint)
        }
        .help(help)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Texty (#334)

    /// `dnes 14:20 · proti 9c1de02` — kdy se předávalo a proti čemu.
    ///
    /// **Absolutní čas, jak ho má návrh**, ne „před 20 minutami“: k razítku patří hlava, a ta se
    /// z relativního času nedá spárovat s commitem v seznamu. Den se píše jen tehdy, když to nebylo
    /// dneska — „dnes“ u týden starého předání by bylo nepravdivé a datum u dnešního šum.
    ///
    /// Hlava chybí jedině tehdy, když se předávalo dřív, než dorazil detail PR; pak to musí být
    /// napsané, protože se z toho neví, jestli zadání ještě platí.
    nonisolated static func stampLabel(of handoff: Handoff) -> String {
        let when = Calendar.current.isDateInToday(handoff.at)
            ? "dnes \(handoff.at.formatted(date: .omitted, time: .shortened))"
            : handoff.at.formatted(date: .abbreviated, time: .shortened)
        guard let head = handoff.shortHead else { return "\(when) · hlavu PR jsem tehdy neznal" }
        return "\(when) · proti \(head)"
    }

    /// Věta pod razítkem, když něco zbývá — **kolik** a proč se to objevilo.
    ///
    /// U neznámé hlavy říká něco jiného: nezbylo nic nového, jen se nedá potvrdit, že předané
    /// platí. Splynutí obou vět by tvrdilo, že přišla práce, která nepřišla.
    nonisolated static func pendingNotice(_ report: HandoffReport) -> String {
        guard report.stage != .unverified else {
            return "Předávalo se dřív, než dorazil detail PR, takže se nedá poznat, jestli zadání "
                + "ještě platí. Sestav ho znovu — tentokrát se hlava zapíše."
        }
        // Posunutá hlava má **vlastní větu**, i když stav není `.outdated`: pod předaným zadáním se
        // změnil kód, a to je jiná informace než „přibyla položka“.
        //
        // **O nálezech se u ní nic netvrdí** (nálezem Copilota na #373, sekce *Suppressed
        // comments*): do tohohle stavu se PR dostane dvěma cestami — review doběhlo proti dnešní
        // hlavě, **nebo** na PR nejsou nálezy vůbec —, takže „nálezy už platí pro dnešní kód“ by
        // v té druhé mluvilo o nálezech, které neexistují. Že se review pouštět nemusí, je vidět
        // z toho, co panel **nekreslí**: varování ani `Pustit review znovu`.
        guard !report.hasMovedHead else {
            let against = report.handoff?.shortHead.map { " proti \($0)" } ?? ""
            return "Od předání\(against) přišel nový commit — sestav zadání znovu, ať agent dostane, "
                + "co platí pro dnešní kód."
        }
        let items = Plural.czech(report.pending, one: "položka", few: "položky", many: "položek")
        return "Od předání \(Plural.word(report.pending, one: "přibyla", few: "přibyly", many: "přibylo")) "
            + "\(items) — sestav zadání znovu, ať v něm je."
    }

    /// Varování po pushi: proti čemu se předávalo, kolik commitů přišlo a co s tím.
    ///
    /// Počet commitů se píše **jen když se ví** (seznam commitů se načetl a předaná hlava v něm
    /// je). Po force pushi ani nad nenačteným seznamem se dopočítat nedá, a číslo, které by z toho
    /// vyšlo, by o pushnutých commitech nemluvilo.
    nonisolated static func outdatedNotice(_ report: HandoffReport) -> String {
        let against = report.handoff?.shortHead.map { "proti \($0)" } ?? "proti starší hlavě"
        let arrived: String
        switch report.commits {
        case .some(let count) where count > 0:
            arrived = "mezitím \(Plural.word(count, one: "přišel", few: "přišly", many: "přišlo")) "
                + Plural.czech(count, one: "commit", few: "commity", many: "commitů")
        default:
            arrived = "mezitím se hlava PR posunula"
        }
        return "Předával jsi \(against), \(arrived). Nálezy platí pro starý kód — než sestavíš "
            + "nové zadání, pusť review znovu."
    }

    // MARK: - Rozdělané review z dřívějška

    /// Draft, který na vlastním PR zbyl z doby, kdy se tam zakládat dal.
    ///
    /// **Nezahazuje se sám a nemizí.** Odeslat ho nejde (GitHub review na vlastní PR odmítne),
    /// ale tiše zmizelá data jsou horší než data, která nejdou odeslat — takže je vidět, co v něm
    /// je, a jde smazat. Komentáře se dají otevřít i v diffu, kde jim bublina zůstává.
    private func leftover(_ draft: ReviewDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Rozdělané review z dřívějška")
            // **Ne „GitHub review nepřijme“**: `COMMENT` by tam prošel (změřeno u #62), takže by
            // ta věta tvrdila víc, než je změřené. Odsud se review nesbírá, a to je to, co platí.
            Text("Odeslat ho odsud nejde — na vlastním PR se review nesbírá. Zůstává tady, aby se dalo přečíst a smazat.")
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if !draft.body.isEmpty {
                Text(verbatim: draft.body)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(draft.comments) { comment in
                Text(verbatim: "\(Policy.location(of: comment)) — \(comment.body.singleLine)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Zahodit review", systemImage: "trash") {
                isConfirmingDiscard = true
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .confirmationDialog(
                "Zahodit rozdělané review?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Zahodit", role: .destructive) { discardDraft() }
                Button("Zpět", role: .cancel) {}
            } message: {
                Text("Tělo, verdikt i všechny řádkové komentáře. Zpátky to nejde.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.stale.opacity(0.11), in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.stale.opacity(0.4)) }
    }

    // MARK: - Patička

    /// Patička na hraně panelu, jak ji má návrh (`.composer`). **Tři podoby podle stavu předání**
    /// (#334): sestavit, sestavit znovu, nebo pustit review.
    private var composer: some View {
        // Mezera 9 bodů je z návrhu (`.composer { gap: 9px }`) — patička nese dvě akce pod sebou.
        VStack(spacing: 9) {
            switch report.stage {
            case .outdated:
                primaryButton(
                    isReviewing ? "Review běží…" : "Pustit review znovu →",
                    isEnabled: !isReviewing,
                    help: isReviewing
                        ? "Review na tomhle PR už běží — druhé kolo na tentýž commit jsou peníze za nic"
                        : "Spustí review skilly proti dnešní hlavě. Samo se to nepustí nikdy — automat se vlastních PR netýká (#332).",
                    action: runReview
                )
                // **Druhá cesta zůstává** (#334): nové vlákno od kolegy se dá předat i bez nového
                // review a bývá to nejrychlejší kolo. Zakázat to by nutilo pouštět reviewery
                // kvůli jedné větě.
                //
                // **Když není co předat, není tam tlačítko, ale věta.** `AccentLinkButtonStyle`
                // kreslí akcent bez ohledu na `disabled`, takže zakázaný odkaz vypadá jako
                // klikatelný — a kliknutí, po kterém se nic nestane, je k nerozeznání od rozbité
                // aplikace. Věta navíc řekne **proč**, což zakázané tlačítko neumí.
                if report.freshDiscussion.isEmpty {
                    Text("Nové vlákno tu není, takže není co předat samostatně.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: composeFresh) {
                        Text("Sestavit i tak (jen nové vlákno)")
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.accentLink)
                    .help("Sestaví zadání jen z toho, co po předání přibylo v diskuzi — bez nálezů, které platí pro starý kód")
                }
            case .delivered:
                // Tlumené, ne plné akcentové: všechno je předané, takže tohle není akce, kterou
                // by panel doporučoval — jen cesta, jak si text vyzvednout znovu. Prázdné zadání
                // dostane věta místo zakázaného odkazu, ze stejného důvodu jako u `Sestavit i tak`.
                if prompt.isEmpty {
                    Text("Zapni volbu, ve které něco je, a zadání se dá sestavit znovu.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: compose) {
                        Text("Sestavit znovu")
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.accentLink)
                    .help("Ukáže tentýž text znovu — zkopírovat nebo uložit se dá až tam. Nikam se to neodesílá.")
                }
            case .never, .changed, .unverified:
                primaryButton(
                    "Sestavit prompt →",
                    isEnabled: !prompt.isEmpty,
                    help: prompt.isEmpty
                        ? "Není co předat — zapni volbu, ve které něco je, nebo pusť review"
                        : "Ukáže celý text; zkopírovat nebo uložit se dá až tam. Nikam se to neodesílá.",
                    action: compose
                )
            }
        }
        .padding(11)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    /// Plné tlačítko z návrhu (`.composer .send`). Zakázané je **s důvodem**, ne mlčky: tlačítko,
    /// po kterém se nic nestane, je k nerozeznání od rozbité aplikace.
    private func primaryButton(
        _ label: String,
        isEnabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isEnabled ? Palette.surface : Palette.ink3)
                .background(isEnabled ? Palette.accent : Palette.raised, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }
}
