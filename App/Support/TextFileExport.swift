import AppKit

/// Uložení textu do souboru, který si vybere člověk (#333).
///
/// **Jediné místo v aplikaci, které zapisuje mimo její cache** — a smí to jedině proto, že cestu
/// vybírá uživatel v systémovém dialogu. Tvrdá podmínka č. 3 (nikdy nesahat na cizí klony) tím
/// není dotčená: nic se nehledá ani nepřepisuje samo, `NSSavePanel` se na přepsání ptá sám.
///
/// Chyba se **vrací**, ne spolkne: zadání, které se „uložilo“ na plný disk, vypadá jako uložené
/// a člověk ho po zavření okna nemá kde vzít znovu.
enum TextFileExport {
    /// Nabídne dialog a zapíše text. `nil` = člověk to zrušil (není to chyba).
    @MainActor
    static func save(_ text: String, suggestedName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        // **Bez `allowedContentTypes`**, schválně: `.md` sice na `public.plain-text` sedí, ale
        // panel si k názvu dopisuje příponu podle prvního povoleného typu — a ze `zadani.md` by
        // se stalo `zadani.md.txt`. Přípona je v navrženém názvu (`Policy.agentPromptFileName`)
        // a kdo ji chce jinou, si ji přepíše.
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
