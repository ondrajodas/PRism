import SwiftUI

/// Potvrzení odeslání review — poslední obrazovka před tím, než něco opustí stroj.
///
/// **Dvě kliknutí, dvě různá tlačítka.** „Odeslat review…“ v panelu jen otevře tenhle sheet;
/// teprve tlačítko tady zavolá publisher. Zavřít se dá kdykoli a draft tím zůstane netknutý.
///
/// Ochrana stojí na **úplném výpisu toho, co odejde** — ne na opisování názvu repa a ne na
/// druhém dialogu nad tímhle. Obojí je divadlo, které se za týden odklikává poslepu, a pak
/// je slabší i to první potvrzení. Proto je tady vidět tělo review i každý řádkový komentář,
/// tak jak půjdou do payloadu.
struct ReviewSubmissionSheet: View {
    let submission: ReviewSubmission
    let close: () -> Void

    /// Rozhodnutí z kontroly kotev (#69). Drží je okno, protože potvrzovací tlačítko je v patičce.
    @State private var choices: [UUID: DraftTransferChoice] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView { content.padding(16) }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 420, idealHeight: 560)
        // Zavřít okno uprostřed volání by znamenalo nevědět, jestli review odešlo. `gh` má
        // třicetivteřinový timeout, takže to čekání je ohraničené.
        .interactiveDismissDisabled(submission.state == .sending)
    }

    /// Dvě stránky v jednom okně (#69): dokud je draft psaný proti staršímu commitu, je vidět
    /// kontrola kotev; po přenesení payload, který odejde.
    @ViewBuilder private var content: some View {
        if submission.state == .checking {
            DraftTransferView(
                anchors: submission.anchors,
                head: submission.pullRequest.id.description,
                choices: $choices
            )
        } else {
            payload
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zkontroluj, co odejde na GitHub")
                .font(.headline)
            // `verbatim` a ruční skládání: `Text("…#\(number)")` by číslo PR prohnalo
            // locale a z #21663 udělalo „#21 663“.
            Text(verbatim: submission.pullRequest.id.description)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(verbatim: submission.pullRequest.title)
                .font(.callout)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Co odejde

    private var payload: some View {
        VStack(alignment: .leading, spacing: 16) {
            verdictSection
            if submission.contradictsSuggestion { contradiction }
            bodySection
            commentsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Zvolený verdikt a **vedle něj** návrh z nálezů. Návrh nic nepředvyplňuje — v tuhle
    /// chvíli je volba dávno hotová a tohle je poslední místo, kde se dá porovnat.
    private var verdictSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Verdikt")
            HStack(spacing: 10) {
                if let verdict = submission.verdict {
                    Label {
                        // Anglický `event` schválně vedle českého popisku: `APPROVE` je to,
                        // co se doopravdy zapíše na GitHub, a v tlačítku dole stojí totéž.
                        Text(verbatim: "\(verdict.czechLabel) · \(verdict.rawValue)")
                            .font(.callout.weight(.semibold))
                    } icon: {
                        Image(systemName: verdict.symbolName)
                    }
                    .foregroundStyle(verdict.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(verdict.tint.opacity(0.12), in: .rect(cornerRadius: 6))
                }
                Text(verbatim: suggestionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var suggestionText: String {
        switch submission.suggestion {
        case .approve: "Návrh z nálezů: approve"
        case .requestChanges: "Návrh z nálezů: request changes"
        case nil: "Návrh z nálezů: není z čeho soudit"
        }
    }

    /// Rozchod mezi mojí volbou a návrhem z nálezů. **Není to zákaz** — nálezy jsou návrh
    /// a přebít se smějí. Ale schválit PR, u kterého reviewer hlásí blokující nález, je ta
    /// nejdražší záměna, jakou tohle okno umí, takže se to říká nahlas.
    private var contradiction: some View {
        Label {
            Text("Tvoje volba se rozchází s návrhem z nálezů. Zkontroluj, jestli je to záměr.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 6))
    }

    /// Tělo se ukazuje **tak, jak je napsané**, ne vyrenderované.
    ///
    /// Je to potvrzení payloadu, ne náhled na GitHubu: permalinky, ze kterých GitHub udělá
    /// úryvek kódu, musí být vidět jako odkazy, jinak se nedá zkontrolovat, kam míří.
    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Tělo review")
            if submission.draft.body.isEmpty {
                // „Odejde samotný verdikt“ by lhalo u draftu, který má řádkové komentáře —
                // ty odcházejí týmž voláním a jsou hned pod tímhle.
                Text("Prázdné — review odejde bez souhrnu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                monospaced(submission.draft.body)
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(commentsTitle)
            if comments.isEmpty {
                Text("Žádné — nic se neváže ke konkrétnímu řádku.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                    }
                }
            }
        }
    }

    private var comments: [ReviewDraftComment] { submission.draft.comments }

    private var commentsTitle: String {
        comments.isEmpty ? "Řádkové komentáře" : "Řádkové komentáře · \(comments.count)"
    }

    private func commentRow(_ comment: ReviewDraftComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: Policy.location(of: comment))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Zepředu, ať zůstane jméno souboru a číslo řádku — stejně jako
                    // ve sloupci `Místo` v tabulce nálezů.
                    .truncationMode(.head)
                if let reviewer = comment.origin.reviewer {
                    Text(verbatim: "z nálezu · \(reviewer)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            monospaced(comment.body)
        }
    }

    private func monospaced(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(.callout, design: .monospaced))
            // Text ke kopírování a je ho málo — tohle není líný seznam s tisíci `Text`y,
            // kvůli kterému výběr nad diffem není.
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Patička

    private var footer: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 12)
            buttons
        }
        .padding(16)
    }

    @ViewBuilder private var status: some View {
        switch submission.state {
        case .ready:
            EmptyView()
        case .checking:
            checkingStatus
        case .sending:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Odesílám…").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: error.userDescription)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(.red)
                // Že draft zůstal, musí být **vidět**, ne v nápovědě: po červené hlášce se
                // jinak čeká, že se rozepsaná práce ztratila, a člověk ji začne psát znovu.
                Text(verbatim: aftermath(of: error))
                    .font(.caption)
                    .foregroundStyle(error.mightHaveReachedGitHub ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .sent(let review):
            Label {
                Text(verbatim: sentText(review))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.callout)
            .foregroundStyle(.green)
        }
    }

    /// Kolik kotev si žádá rozhodnutí. Bez toho by se u dlouhého seznamu dalo přehlédnout, že se
    /// něco ztratilo — a ztracená kotva je jediná věc, kterou GitHub odmítne i s celým review.
    @ViewBuilder private var checkingStatus: some View {
        let needsAttention = submission.anchors.filter { $0.state == .lost || $0.state == .uncertain }.count
        if needsAttention > 0 {
            Label(
                "\(Plural.czech(needsAttention, one: "komentář", few: "komentáře", many: "komentářů")) chce rozhodnout",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    /// Co se stalo s draftem — a jestli se to smí zkusit znovu.
    ///
    /// **Dvě různé věty schválně.** „Nic se nemazalo, dá se zkusit znovu“ nad chybou, po které
    /// review na PR **může ležet**, je pozvánka k odeslání approve podruhé — a hlášky by si
    /// odporovaly, protože `timedOut` i `malformedResponse` ve svém textu říkají „zkontroluj
    /// to na GitHubu“. Tlačítko je v tom případě zakázané (`canSend`), takže věta a tlačítko
    /// říkají totéž.
    private func aftermath(of error: PublishError) -> String {
        error.mightHaveReachedGitHub
            ? "Rozdělané review zůstalo. Než ho pošleš znovu, zkontroluj PR na GitHubu — jinak tam může být dvakrát."
            : "Rozdělané review zůstalo, nic se nemazalo — dá se zkusit znovu."
    }

    /// Hlásí se, co potvrdil **GitHub**, ne co jsme poslali. Neznámý stav se nedomýšlí —
    /// z něj plyne „zkontroluj to na GitHubu“, ne „proběhlo to, jak jsi chtěl“.
    private func sentText(_ review: SubmittedReview) -> String {
        guard let state = review.state else {
            return "Review odešlo, ale GitHub vrátil stav, kterému nerozumím. Zkontroluj ho na GitHubu."
        }
        return "Review odešlo jako \(state.rawValue)."
    }

    @ViewBuilder private var buttons: some View {
        switch submission.state {
        case .sent:
            Link("otevřít na GitHubu", destination: submission.pullRequest.url)
                .font(.callout)
            Button("Zavřít", action: close)
                .keyboardShortcut(.cancelAction)
        case .checking:
            Button("Zrušit", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
            transferButton
        default:
            Button("Zrušit", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(submission.state == .sending)
            sendButton
        }
    }

    /// První ze dvou kliknutí u zastaralého draftu (#69). Pojmenované **commitem**, na který se
    /// přenáší — z „OK“ by nebylo poznat, co se potvrzuje. Odeslání je až druhé tlačítko, které se
    /// objeví teprve po tomhle.
    private var transferButton: some View {
        Button("Přenést na \(submission.pullRequest.id.description)") {
            submission.transfer(choices: choices)
        }
        .buttonStyle(.borderedProminent)
    }

    /// Tlačítko je pojmenované **akcí**, ne slovem „OK“ — a hlavně **není výchozí**:
    /// `.keyboardShortcut` na něm schválně žádný není, takže Enterem se nic neodešle.
    /// Přebít se to smí jedině vědomě; `.borderedProminent` je vzhled, ne klávesa.
    private var sendButton: some View {
        Button(sendLabel) {
            Task {
                await submission.send()
                // Zavírá se **až po** úklidu, který `send()` čeká: v tu chvíli je za sheetem
                // draft pryč a konverzace načtená znovu, takže se okno neodhalí ve starém
                // stavu. Zelená hláška je do té doby vidět, což je potvrzení bez umělé pauzy.
                if submission.closesItself { close() }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!submission.canSend)
    }

    /// Anglický `event` schválně: `APPROVE` je přesně to, co se zapíše na GitHub, takže se
    /// z tlačítka nedá vyčíst nic jiného, než co se doopravdy stane. Po selhání se text
    /// **nemění** na „Zkusit znovu“ — akce zůstává tatáž a název akce je to, co má tlačítko
    /// říkat; že první pokus nevyšel, stojí vedle v patičce.
    private var sendLabel: String {
        guard let verdict = submission.verdict else { return "Odeslat review" }
        return "Odeslat \(verdict.rawValue) pro \(submission.pullRequest.id)"
    }
}
