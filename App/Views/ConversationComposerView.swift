import SwiftUI

/// Napsat komentář do diskuze pod PR (#216) — pruh na spodní hraně tabu `Konverzace`.
///
/// **Není to review a nesmí s ním splynout.** Review je verdikt nad kódem: jde ven přes
/// potvrzení s vypsaným payloadem a bydlí v panelu `Moje review`. Tohle je jedna věta
/// v diskuzi — nepotvrzuje se, nenese verdikt a v panelu se neobjeví. Proto sedí **pod osou
/// konverzace**, ne v pravém panelu, kam ho kreslí návrh: ten panel je v okně vidět ve všech
/// tabech a jeden z jeho tabů je zrovna `Moje review`, takže by pod sebou stály dvě pole
/// a dvě odesílací tlačítka, z nichž každé dělá něco jiného. Sazba návrhu (pruh s linkou
/// nahoře, pole a odesílací tlačítko) zůstává; mění se, ke kterému sloupci je přilepený.
struct ConversationComposerView: View {
    let text: String
    var viewer: String = ""
    /// Co se právě děje s odesíláním. `nil` = nic.
    var state: CommentActionState?
    /// Proč se odeslat nedá. `nil` = dá. Tlačítko z toho bude **zakázané s důvodem**, ne
    /// schované — chybějící tlačítko vypadá jako rozbitá aplikace, kdežto zakázané s nápovědou
    /// řekne, že se to zapíná v nastavení.
    var block: String?
    var commit: (String) -> Void = { _ in }
    var send: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                AvatarView(login: viewer, url: nil, size: 16)
                // **Strop výšky je tady podstatný**, ne kosmetika. `TextEditor` je svisle
                // nenasytný a osa nad ním je scroll, takže si o zbylou výšku tabu řekli
                // stejným dílem — pole pak zabralo skoro půlku obrazovky a osa, kvůli které
                // se do tabu chodí, se scvrkla na pár řádků. Návrh má `min-height: 46px`;
                // v prohlížeči roste s textem, `TextEditor` v SwiftUI ne (scrolluje uvnitř),
                // takže je z toho pevná výška.
                DraftTextEditor(
                    text: text,
                    placeholder: "Napsat do konverzace pod PR…",
                    minHeight: 46,
                    maxHeight: 46,
                    commit: commit
                )
                .disabled(state?.isBusy == true)
            }
            controls
            failureNote
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if let state, state.isBusy {
                ProgressView().controlSize(.small)
                Text("odesílám komentář…")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 8)
            // **Bez potvrzení**, jako odpověď do vlákna (#73): je to jedna věta v diskuzi
            // a dá se smazat. Potvrzuje se review, protože to je verdikt nad kódem.
            Button("Odeslat komentář") { send() }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 12.5))
                .disabled(block != nil || !hasText || state?.isBusy == true)
                .help(help)
        }
    }

    private var help: String {
        if let block { return block }
        if !hasText { return "Napiš komentář — prázdný GitHub tiše zahodí." }
        return "Odešle komentář do diskuze pod PR. Není to review a nenese verdikt."
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Co se nepovedlo. Text u toho **zůstává** a věta to říká — bez ní se rozepsaná věta
    /// začne psát znovu.
    @ViewBuilder private var failureNote: some View {
        if let failure = state?.failure {
            Label {
                Text(verbatim: "\(failure.userDescription) Text zůstal, dá se zkusit znovu.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.stale)
        }
    }
}
