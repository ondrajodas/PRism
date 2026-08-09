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

    /// **Dvě písmena**, jak je má návrh (`OD`, `VO`, `GA`): jedno se u dvou lidí se stejným
    /// začátkem jména plete a v kolečku je na dvě místo dost. Bere se ze slov jména, a když je
    /// jedno, z jeho začátku — `github-actions[bot]` tak dá `GA`, `odinuv` `OD`.
    ///
    /// `?` u prázdného jména — nemá nastat (aktér bez jména se nekreslí vůbec), ale kolečko bez
    /// obsahu vypadá jako chyba vykreslení.
    private var initial: String {
        let words = Self.words(in: login)
        guard let first = words.first else { return "?" }
        if let second = words.dropFirst().first, let a = first.first, let b = second.first {
            return "\(a)\(b)".uppercased()
        }
        return String(first.prefix(2)).uppercased()
    }

    /// Slova jména. Dělí se na **oddělovačích i na velkém písmenu uvnitř** — přezdívky se píšou
    /// obojím způsobem a `ErikZigo` má dát `EZ`, ne `ER`. Bez toho druhého se z každé
    /// camelCase přezdívky stanou dvě písmena jednoho slova, což o druhém jméně neřekne nic.
    ///
    /// `github-actions[bot]` → `GA`, `ErikZigo` → `EZ`, `odinuv` → `OD` (jedno slovo, takže
    /// první dvě písmena).
    static func words(in login: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in login {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            // Velké písmeno uvnitř slova začíná nové — ale jen po malém, aby se `GHActions`
            // nerozpadlo po písmenech.
            if character.isUppercase, let last = current.last, last.isLowercase {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
