import SwiftUI

/// Obrázek uživatele u události v přehledu (#171).
///
/// Dokud obrázek nedorazí — a když nedorazí vůbec — kreslí **iniciálu v kolečku**. Prázdné
/// místo by se od chybějícího řádku nepoznalo a spinner u šestnáctipixelového obrázku je
/// nepokoj za nic.
struct AvatarView: View {
    let login: String
    let url: URL?
    var size: CGFloat = 16

    /// **Nepovinná závislost**, jako `HealthMonitor` ve `StatusBarView`: bez načteného
    /// loaderu (náhledy, offscreen render v testech) zůstane iniciála a nic se nerozbije.
    @Environment(AvatarLoader.self) private var loader: AvatarLoader?

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.circle)
            // Klíčem je adresa: po překreslení s jiným autorem se musí načíst jeho obrázek.
            .task(id: url) {
                guard let url, let loader else { return }
                await loader.load(url)
            }
            .accessibilityLabel(login)
    }

    @ViewBuilder private var content: some View {
        if let url, let image = loader?.image(for: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Circle()
                .fill(.quaternary)
                .overlay {
                    Text(verbatim: initial)
                        .font(.system(size: size * 0.6, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// První písmeno jména. `?` u prázdného jména — nemá nastat (aktér bez jména se nekreslí
    /// vůbec), ale kolečko bez obsahu vypadá jako chyba vykreslení.
    private var initial: String {
        guard let first = login.first else { return "?" }
        return String(first).uppercased()
    }
}
