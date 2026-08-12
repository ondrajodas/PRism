import SwiftUI

/// Stav pracovní kopie ve stavovém řádku (#218, `.sitem plain`).
///
/// **Přestěhováno z hlavičky PR.** Tam to byla zelená `kopie připravená` pod fialovým
/// `Spustit review` a nad oranžovým návrhem verdiktu — tři hlasité barvy pod sebou, které
/// z pravé strany hlavičky dělaly semafor. Ve stavovém řádku je to, co to doopravdy je:
/// **stav prostředí**, ne údaj o pull requestu, a stojí tam vedle dostupnosti `gh` a `claude`.
///
/// Tichá, bez kapsle (`plain`): je to běžný stav, ne upozornění. Selhaný checkout se sem
/// **nekreslí** — porucha zůstává bannerem v hlavičce, protože se u ní musí vypsat celý
/// výstup `gitu` a z něj se teprve pozná, co dělat dál.
///
/// Kreslí se jen nad otevřeným pull requestem: na domácí záložce není o čí kopii mluvit.
struct WorkingCopyStatusView: View {
    let store: AppStore

    var body: some View {
        if case .pullRequest(let id) = store.activeTab {
            content(for: id)
        }
    }

    @ViewBuilder private func content(for id: PRIdentifier) -> some View {
        let state = store.checkoutState(for: id.repo)
        if let text = Self.text(state, head: head(of: id)) {
            HStack(spacing: 5) {
                if case .preparing = state {
                    ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 9, height: 9)
                }
                Text(verbatim: text)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .monospacedDigit()
                if case .absent = state {
                    Button("Připravit") {
                        Task { await store.prepareCheckout(for: id) }
                    }
                    // **Akcent z palety, i když návrh o téhle akci nic neříká** (#298): `Připravit`
                    // v mockupu nakreslené není, jeho stavový řádek zná jen texty a puntíky. Mlčení
                    // návrhu ale není povolení k systémové modré — „jedna barva pro klikni sem“ je
                    // vlastnost **celého okna**, takže ponechat tady `.link` znamená přestěhovat ta
                    // dvě různá „klikni sem“ o pruh níž, ne je zrušit. Že paleta do stavového řádku
                    // dosahuje, návrh potvrzuje sám: zastaralé nálezy v něm barví `var(--stale)`.
                    .buttonStyle(.accentLink)
                    .font(.caption)
                }
            }
            .help(Self.help(state))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pracovní kopie")
            .accessibilityValue(text)
        }
    }

    /// Hlava PR na sedm znaků. `nil`, dokud detail nedorazil — hádat se nedá a zkrácená sha
    /// je přesně ten údaj, který se z pruhu opisuje do terminálu.
    private func head(of id: PRIdentifier) -> String? {
        guard case .loaded(let detail, _) = store.detailState(for: id) else { return nil }
        return String(detail.headSha.prefix(7))
    }

    /// Věta do pruhu. `nil` u selhání — to patří do banneru v hlavičce, ne sem.
    nonisolated static func text(_ state: CheckoutState, head: String?) -> String? {
        let copy: String? = switch state {
        case .ready: "Pracovní kopie připravená"
        case .preparing: "Připravuji pracovní kopii…"
        case .absent: "Pracovní kopie zatím není"
        case .failed: nil
        }
        guard let copy else { return nil }
        guard let head else { return copy }
        return "\(copy) · HEAD \(head)"
    }

    /// Cesta ke klonu visí na nápovědě: potřeba je zřídka, ale v pruhu by zabrala všechno
    /// místo — je to sedmdesát znaků cache.
    nonisolated static func help(_ state: CheckoutState) -> String {
        switch state {
        case .ready(let path):
            "Klon v cache aplikace:\n\(path.path(percentEncoded: false))"
        case .preparing:
            "Klonuje se do cache aplikace. Na tvoje klony se přitom nesahá."
        case .absent:
            "Klon se připraví sám při spuštění review; tímhle jde stáhnout dopředu."
        case .failed:
            "Pracovní kopii se nepodařilo připravit — podrobnosti jsou v hlavičce."
        }
    }
}
