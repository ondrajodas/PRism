import SwiftUI

/// Tab `Moje review` ve spodním panelu: verdikt, tělo review a seznam řádkových komentářů.
///
/// Je to **domov draftu** — v diffu jsou vidět jen komentáře, které se dají zakotvit, takže
/// tady je jediné místo, kde je vidět celý obsah toho, co se odešle. Komentář na řádku, který
/// v aktuálním diffu není (přišel nový commit), by jinak nešlo ani najít, ani smazat.
///
/// Odeslání tady **není**: to je #68. Tenhle panel jen skládá, co se pošle.
struct DraftPanel: View {
    /// Ke kterému PR panel patří. Není to jen popisek: visí na tom identita editoru těla,
    /// a ta rozhoduje, kam se doručí rozepsaný text při přepnutí PR.
    let pullRequest: PRIdentifier
    let draft: ReviewDraft?
    /// Je draft psaný proti staršímu commitu, než je hlava PR?
    var isStale = false
    /// Proč se do draftu nedá psát. `nil` = dá se.
    var unavailable: String?
    var actions = DraftActions()
    var jump: (ReviewDraftComment) -> Void = { _ in }

    @State private var isConfirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStale { staleBanner }
            if let unavailable { unavailableNote(unavailable) }
            topRow
            editors
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Hlavička

    /// Zastaralý draft se **nemaže** — jen se nedá odeslat. Vlastní próza je dražší než
    /// strojový nález, takže se nechává s poctivým příznakem; přenesení na nový commit je #69.
    private var staleBanner: some View {
        Label {
            Text("Review je psané proti staršímu commitu, než je teď v PR. Odeslat se takhle nedá — komentáře by sedly na jiný kód. Text zůstává, nic se nemaže.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 6))
    }

    private func unavailableNote(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            verdictPicker
            Spacer(minLength: 12)
            if draft != nil { discardButton }
        }
    }

    /// Verdikt **bez předvyplnění**: dokud nic nesvítí, nikdo nevybral.
    ///
    /// Tři tlačítka místo `Pickeru`: ten musí mít vybranou hodnotu, takže by v něm musela být
    /// čtvrtá, falešná („nevybráno“) — a hodnota, kterou GitHubu posílám jako `event`, se od
    /// návrhu aplikace musí dát odlišit na první pohled.
    private var verdictPicker: some View {
        HStack(spacing: 6) {
            Text("Verdikt:")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(ReviewDraft.Verdict.allCases, id: \.self) { verdict in
                verdictButton(verdict)
            }
            if draft?.verdict == nil {
                Text("nevybráno")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Vybraný verdikt je **vyplněný a se zaškrtnutím**, ne jen obarvený.
    ///
    /// Je to hodnota, která jde do `event` — tedy to, co GitHub s PR udělá. Rozdíl mezi
    /// „vybráno“ a „nevybráno“ proto nemá stát jen na odstínu textu: barvy se v tmavém
    /// režimu i u barvosleposti sbíhají a splést si `Vyžádat změny` se `Schválit` je ta
    /// nejdražší záměna, jakou tohle okno umí.
    @ViewBuilder private func verdictButton(_ verdict: ReviewDraft.Verdict) -> some View {
        let isChosen = draft?.verdict == verdict
        let button = Button {
            // Druhé kliknutí volbu ruší — jinak by se vybraný verdikt nedal vzít zpátky
            // a draft by šel zrušit jedině celý.
            actions.setVerdict(isChosen ? nil : verdict)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : symbol(of: verdict))
                Text(verbatim: verdict.czechLabel)
            }
            .font(isChosen ? .callout.weight(.semibold) : .callout)
        }
        .disabled(unavailable != nil)
        .help(help(for: verdict))

        if isChosen {
            button.buttonStyle(.borderedProminent).tint(tint(of: verdict))
        } else {
            button.buttonStyle(.bordered).tint(.secondary)
        }
    }

    private func symbol(of verdict: ReviewDraft.Verdict) -> String {
        switch verdict {
        case .approve: "checkmark.seal"
        case .requestChanges: "exclamationmark.triangle"
        case .comment: "text.bubble"
        }
    }

    /// `Vyžádat změny` je **červené**, ne oranžové.
    ///
    /// Návrh verdiktu z nálezů (`VerdictView`) oranžový zůstává schválně: to je odhad
    /// aplikace, kdežto tohle je rozhodnutí, které odejde na GitHub. Červená se v tomhle okně
    /// drží pro blokující věci a GitHub barví „changes requested“ stejně.
    private func tint(of verdict: ReviewDraft.Verdict) -> Color {
        switch verdict {
        case .approve: .green
        case .requestChanges: .red
        case .comment: .accentColor
        }
    }

    private func help(for verdict: ReviewDraft.Verdict) -> String {
        switch verdict {
        case .approve: "Odešle review jako APPROVE"
        case .requestChanges: "Odešle review jako REQUEST_CHANGES"
        case .comment: "Odešle review bez verdiktu (COMMENT) — na vlastním PR to jediné jde"
        }
    }

    private var discardButton: some View {
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
            Button("Zahodit", role: .destructive) { actions.discard() }
            Button("Zpět", role: .cancel) {}
        } message: {
            Text("Tělo, verdikt i všechny řádkové komentáře. Zpátky to nejde.")
        }
    }

    // MARK: - Obsah

    /// Tělo vlevo, komentáře vpravo. Vedle sebe schválně: panel je nízký pruh a jedno pod
    /// druhým by znamenalo scrollovat mezi dvěma věcmi, které se píšou naráz.
    private var editors: some View {
        HStack(alignment: .top, spacing: 16) {
            bodyEditor
            comments
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tělo review")
                .font(.caption)
                .foregroundStyle(.secondary)
            DraftTextEditor(
                text: draft?.body ?? "",
                placeholder: "Souhrn k celému PR. Nálezy mimo diff se sem přidají jako odkaz na kód.",
                minHeight: 80,
                commit: actions.setBody
            )
            .disabled(unavailable != nil)
            // **Identita per PR, ne per draft.** Panel si SwiftUI mezi pull requesty ponechá
            // (stejná pozice ve stromu), takže bez tohohle by přepnutí PR jen změnilo `text`
            // — a rozepsaná věta by se tiše zahodila. S vlastní identitou se editor zahodí
            // a v `onDisappear` doručí, co v něm bylo. Klíčovat draftem nejde: ten vzniká
            // až prvním uložením, takže by se identita měnila **během** psaní.
            .id(pullRequest)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: commentsTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            if commentList.isEmpty {
                Text("Komentář přidáš tlačítkem, které se objeví na řádku diffu, nebo převzetím nálezu z bubliny.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commentList) { comment in
                            commentRow(comment)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 320, alignment: .topLeading)
    }

    private var commentList: [ReviewDraftComment] { draft?.comments ?? [] }

    private var commentsTitle: String {
        commentList.isEmpty
            ? "Komentáře k řádkům"
            : "Komentáře k řádkům · \(commentList.count)"
    }

    private func commentRow(_ comment: ReviewDraftComment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                jump(comment)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // Zepředu, ať zůstane jméno souboru a číslo řádku — stejně jako ve
                        // sloupci `Místo` v tabulce nálezů.
                        Text(verbatim: location(of: comment))
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                        if comment.origin.reviewer != nil {
                            Image(systemName: "text.magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Vznikl převzetím nálezu")
                        }
                    }
                    Text(verbatim: preview(of: comment))
                        .font(.caption)
                        .foregroundStyle(comment.body.isEmpty ? .orange : .secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Odskočit na komentář v diffu")

            Button("Vyjmout", systemImage: "trash") {
                actions.removeComment(comment.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Vyjmout komentář z rozdělaného review")
        }
        .padding(.vertical, 6)
    }

    private func location(of comment: ReviewDraftComment) -> String {
        // `verbatim` a ruční skládání: `Text("…\(line)")` by číslo řádku prohnalo locale
        // a z 21663 udělalo „21 663“.
        let side = comment.side == .left ? " (starý)" : ""
        return "\(comment.path):\(comment.line)\(side)"
    }

    private func preview(of comment: ReviewDraftComment) -> String {
        // „Zahodí se“, ne „neuloží se“: v draftu prázdný komentář chvíli je, jen nepřežije
        // odchod z bubliny ani restart. Tatáž věta je i v bublině a musí říkat totéž.
        guard !comment.body.isEmpty else { return "prázdný — zahodí se" }
        return comment.body.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
