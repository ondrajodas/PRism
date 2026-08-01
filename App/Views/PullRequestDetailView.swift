import SwiftUI

/// Pravý panel: co víme o vybraném PR a co se s ním dá zatím dělat.
///
/// Diff a nálezy sem přijdou v dalších fázích; teď tu žije příprava pracovní kopie —
/// včetně toho, co řekl `git`, když se nepovedla.
struct PullRequestDetailView: View {
    let store: AppStore
    let pullRequest: PullRequestSummary


    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            checkout
            Spacer()
            Text("Diff a nálezy sem přijdou v dalších fázích.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Klon je jeden pro celé repo, takže druhé PR ze stejného repa může mít hotovo,
        // aniž by o tom kdo řekl. Zjistí se to při výběru řádku, ne klonováním.
        .task(id: pullRequest.id) { await store.noteExistingCheckout(for: pullRequest.id) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pullRequest.title).font(.title2)
            HStack(spacing: 6) {
                Text(pullRequest.id.description).foregroundStyle(.secondary)
                Link("otevřít na GitHubu", destination: pullRequest.url).font(.callout)
            }
        }
    }

    /// Vždycky podle stavu ve store, nikdy podle vlastního `@State`. `PullRequestDetailView`
    /// si SwiftUI mezi PR drží (stejná pozice ve stromu), takže vlastní příznak by přetekl
    /// z jednoho pull requestu na druhý.
    @ViewBuilder private var checkout: some View {
        switch store.checkoutState(for: pullRequest.repo) {
        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Připravuji pracovní kopii… U velkého repa to chvíli trvá.")
            }
        case .failed(let detail):
            failure(detail)
        case .ready(let path):
            ready(path)
        case .absent:
            Button("Připravit pracovní kopii", systemImage: "arrow.down.circle", action: prepare)
        }
    }

    /// Vlastní rámeček místo `GroupBox`u: ten je AppKit kontejner a `ImageRenderer` ho
    /// nevykreslí, takže by tenhle stav nešlo zkontrolovat jinak než ručně v aplikaci.
    private func failure(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pracovní kopii se nepodařilo připravit", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            // Text od `gitu` je to, z čeho se pozná, co dělat dál — proto celý
            // a k vybrání, ne zkrácený do jedné věty.
            Text(detail)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                // Bez `fixedSize` se dlouhý výstup `gitu` ořízne a nejde ani zkopírovat —
                // přitom právě z něj se pozná, co se stalo.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Zkusit znovu", systemImage: "arrow.clockwise", action: prepare)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    private func ready(_ path: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pracovní kopie připravená", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            Text(path.path(percentEncoded: false))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func prepare() {
        Task { await store.prepareCheckout(for: pullRequest.id) }
    }
}
