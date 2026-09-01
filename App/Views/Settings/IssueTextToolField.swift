import SwiftUI

/// Jméno MCP nástroje na text issue v nastavení (#389) — jedno pole a **věta pod ním**.
///
/// Vlastní view kvůli té větě, ne kvůli poli: prázdná hodnota tady znamená `netahat`, a to je
/// stav, který se z prázdného pole poznat nedá. Bez věty pod polem by prázdno vypadalo jako
/// nedodělek a vyplněné jméno by mlčelo o tom, že u PR s odkazem poběží session navíc.
///
/// **Rozhoduje `Policy.issueTextToolNote(for:)`**, ne tohle view: je to tatáž hodnota, podle které
/// se pak na cestě review tahá nebo netahá, takže se o ní nesmí rozhodovat dvakrát.
struct IssueTextToolField: View {
    /// `nil` i prázdný řetězec znamenají `netahat`; drží se ten rozdíl, na který se dá zapsat
    /// **chybějící klíč** v souboru.
    @Binding var tool: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Nápověda patří do `prompt:` — první argument by se ve `Form`u vykreslil jako
            // popisek vlevo od pole, takže by u vyplněného řádku stály dvě hodnoty vedle sebe.
            // Vyplněný ale zůstává: `.labelsHidden()` ho skryje jen vizuálně, pro VoiceOver je
            // to jediný popis pole.
            TextField(
                "Jméno MCP nástroje",
                text: name,
                prompt: Text(verbatim: IssueTextTool.namePattern)
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            // Monospace jako u dotazu ve zdrojích: je to identifikátor, ne próza, a záleží
            // v něm na podtržítkách.
            .font(.system(.body, design: .monospaced))

            note
        }
    }

    /// Stav hodnoty pod polem. Varování se sází jako stížnost u limitu běhu a u promptu — je to
    /// tentýž druh sdělení („takhle napsané to nebude fungovat, jak čekáš“).
    @ViewBuilder private var note: some View {
        let note = Policy.issueTextToolNote(for: tool)
        if note.isWarning {
            Label(note.text, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.find)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(verbatim: note.text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Prázdné pole se ukládá jako **chybějící klíč**, ne jako prázdný řetězec: v souboru pak není
    /// řádek, který tvrdí „nástroj je nastavený na nic“. Pro chování je to jedno
    /// (`Policy.issueTextTool(from:)` bere obojí jako `netahat`), pro toho, kdo soubor čte, ne.
    ///
    /// Bílé znaky se **nechávají, jak jsou napsané**. Ořezávat je při psaní znamená hýbat kurzorem
    /// pod rukou; na cestě do běhu i ve větě pod polem se orážejí obě stejně.
    private var name: Binding<String> {
        Binding(
            get: { tool ?? "" },
            set: { newValue in tool = Policy.issueTextToolEdit(typed: newValue) }
        )
    }
}
