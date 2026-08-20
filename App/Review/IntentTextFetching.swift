import Foundation

/// Co z dotažení textu issue vyleze (#345).
///
/// Nese **obojí naráz**, ne jedno nebo druhé: dotažení se může povést částečně (tři odkazy, dva
/// texty), takže „texty“ a „proč něco chybí“ nejsou dvě alternativy, ale dvě poloviny jedné
/// odpovědi. `Result` by z toho udělal volbu a částečný výsledek by se zahodil.
struct IntentTextResult: Equatable, Sendable {
    var issues: [IntentIssueText] = []
    /// `nil` = nechybí nic. Co který případ znamená, je u `IntentGap`.
    var gap: IntentGap?
}

/// Dotažení textu issue z trackeru — **jen čtení textu, nic jiného** (#345).
///
/// Za protokolem ze stejného důvodu jako `FindingTranslating`: v testech se nahradí fakem a **z typu
/// je vidět, co to umí**. Jedna metoda, která bere odkazy a vrací texty; není tu nic, čím by se dalo
/// zapsat nebo odeslat, takže tvrdá podmínka č. 1 se tímhle nemění.
///
/// **Aplikace neumí Linear API.** Text jde přes `claude`, který k trackeru přístup má — žádný druhý
/// token, žádný modul, žádná nová síťová cesta. Tvrdá podmínka č. 4 mluví o GitHubu, ale přidat
/// vedle ní druhý token by to pravidlo obešlo, ne změnilo.
protocol IntentTextFetching: Sendable {
    /// - Parameters:
    ///   - links: odkazy na zadání, v pořadí, ve kterém se mají v souboru objevit.
    ///   - tool: jméno MCP nástroje z konfigurace (`Policy.issueTextTool`). Volající ho už má
    ///     ověřený jako neprázdný — chybějící hodnota znamená „netahat“, takže se sem s ní
    ///     nechodí.
    /// - Returns: texty a případný důvod, proč některý chybí. **Nevyhazuje na selhání dotažení** —
    ///   to je součást odpovědi (`gap`), ne chyba: review bez textu issue je horší review, ne
    ///   rozbité review. Vyhodí jedině `CancellationError`, protože zrušení není selhání dotažení
    ///   a spolknout ho znamená pokračovat v práci, o kterou si nikdo neřekl.
    func fetchText(of links: [IntentLink], using tool: String) async throws -> IntentTextResult
}
