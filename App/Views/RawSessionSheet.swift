import AppKit
import SwiftUI

/// Sheet se surovou session — **záchranná brzda pod výpisem kroků** (#327, sekce 20 návrhu).
///
/// Výpis kroků o patro výš odpovídá na „koukal se tam, kam měl“. Tohle je na jinou otázku: *proč to
/// dopadlo takhle*, *co dělal, než to spadlo* — a odpověď na ni je v tom, co výpis **schválně
/// zahazuje**: v próze modelu, v jeho uvažování, ve výstupech nástrojů a v systémových událostech.
///
/// **Není to terminál a nemá být**: čte se, nepíše se do toho, a cesta zpátky do session zůstává
/// `Zkopírovat resume` v hlavičce dráhy. Surová session je *víc dat*, ne *jiná schopnost*.
///
/// **Zkrácení se přiznává třikrát** — v hlavičce (`konec souboru, N událostí z posledních 4 MB`),
/// řezem na začátku textu a u ořezané události na místě řezu. Tiše zkrácený přepis tvrdí, že session
/// začala uprostřed.
struct RawSessionSheet: View {
    let target: RawSessionTarget
    let state: RawTranscriptState
    /// Kolik od otevření přibylo. `nil` = nepřibylo nic.
    let growth: Int?
    /// Cesta k souboru — `Zkopírovat cestu k transcriptu` a `Ukázat v Finderu`.
    let path: URL
    let reload: () -> Void
    /// Přeměří velikost souboru. Volá se z odloženého úkolu, viz `growthTick`.
    let refreshSize: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var didCopy = false

    /// Jak často se přeměřuje velikost souboru pro patičku.
    ///
    /// **Dvě vteřiny, a je to jeden dotaz na atributy souboru** — ne druhé čtení okna. Rychlejší
    /// takt by patičce nic nepřidal (přírůstek se čte, ne sleduje) a pomalejší by u běžící session
    /// tvrdil starší číslo, než jaké je pravda.
    private static let growthTick = Duration.seconds(2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 940, minHeight: 420, idealHeight: 640)
        // Ať uvnitř sheetu nikdo šířku nevyjednává (#220) — obsah ji má znát.
        .availableWidth(940)
        // Přírůstek se přeměřuje **v odloženém úkolu, ne v těle**: I/O v `body` by běželo při každém
        // překreslení, a to je zrovna ta třída chyb, kterou popisuje #224.
        .task(id: target) {
            while !Task.isCancelled {
                await refreshSize()
                try? await Task.sleep(for: Self.growthTick)
            }
        }
    }

    // MARK: - Hlavička

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: RawSessionText.title(skill: target.skill))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(verbatim: RawSessionText.slug(target))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if case .shown(let transcript) = state { subtitle(of: transcript) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
    }

    /// **První ze tří přiznání zkrácení** — a vedle něj počet řádků, které se nepodařilo přečíst.
    /// Bez toho druhého by přepis, ze kterého se dala přečíst polovina, vypadal jako celý.
    private func subtitle(of transcript: RawTranscript) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: RawSessionText.subtitle(transcript))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink3)
            if let unreadable = RawSessionText.unreadableLines(transcript) {
                Text(verbatim: unreadable)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.stale)
            }
        }
    }

    // MARK: - Obsah

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            notice {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: RawSessionText.loading)
                        .font(.callout)
                        .foregroundStyle(Palette.ink2)
                }
            }
        case .shown(let transcript):
            TranscriptTextView(transcript: transcript, colorScheme: colorScheme)
                .background(Palette.chrome)
        case .missing, .unreadable, .empty:
            notice { failure }
        }
    }

    /// Hláška pro stav, ve kterém přepis není. **Krátký titulek nad větou**, jak to má návrh
    /// (`.rawstate .who`): z něj je na první pohled poznat, který ze tří stavů to je — a právě to,
    /// že se od sebe poznají, je celý smysl toho, že jsou tři.
    @ViewBuilder private var failure: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title = RawSessionText.failureTitle(state) {
                Text(verbatim: title)
                    .font(.system(size: 9.5, design: .monospaced))
                    .kerning(0.8)
                    .foregroundStyle(Palette.ink3)
            }
            if let message = RawSessionText.failure(state) {
                Text(verbatim: message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func notice<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(Palette.surface)
    }

    // MARK: - Patička

    private var footer: some View {
        HStack(spacing: MiniButtonStyle.Metrics.spacing) {
            ForEach(Policy.rawSessionActions(for: state), id: \.self) { action in
                button(action)
            }
            Spacer(minLength: 8)
            if let growth = RawSessionText.growth(growth) {
                Text(verbatim: growth)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.find)
                    .monospacedDigit()
                    .help("Přepis je snímek k okamžiku otevření. Tolik do souboru přibylo od té chvíle.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.chrome)
    }

    /// `Načíst znovu` je **jediná hlavní akce** v řadě — dvě plná tlačítka vedle sebe znamenají, že
    /// se hlavní akce nedá poznat.
    private func button(_ action: RawSessionAction) -> some View {
        Button(label(of: action)) { perform(action) }
            .buttonStyle(MiniButtonStyle(emphasis: action == .reload ? .primary : .secondary))
            .keyboardShortcut(action == .close ? .cancelAction : nil)
    }

    private func label(of action: RawSessionAction) -> String {
        guard action == .copyTranscript, didCopy else { return RawSessionText.action(action) }
        return "Zkopírováno"
    }

    private func perform(_ action: RawSessionAction) {
        switch action {
        case .close:
            dismiss()
        case .copyTranscript:
            guard case .shown(let transcript) = state else { return }
            // Skládá se **až při kliknutí**: přepis má po ořezu megabajty, takže by se jinak stavěl
            // při každém překreslení patičky, tedy i při každém tiknutí přírůstku.
            Clipboard.copy(RawSessionScript.plain(RawSessionScript.lines(of: transcript)))
            didCopy = true
        case .copyPath:
            Clipboard.copy(path.path(percentEncoded: false))
        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([path])
        case .reload:
            didCopy = false
            reload()
        }
    }
}
