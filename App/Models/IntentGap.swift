import Foundation

/// Proč zadání pro reviewera **není celé** (#345).
///
/// Existuje kvůli jedné jediné otázce, na kterou musí umět odpovědět jak soubor se zadáním, tak
/// osa v tabu `Průběh`: **„issue nic neříká“, nebo „text se nedotáhl“?** Bez rozlišení vypadá
/// review, které zadání nevidělo, stejně jako to, které ho vidělo — a to je ta nejdražší záměna,
/// jakou tahle aplikace umí vyrobit.
///
/// **Rozhoduje se podle `init.mcp_servers[].status`, ne podle prózy modelu**, a je to změřené,
/// ne odhad. Průzkum u #345 naměřil **tři různé tvary selhání a dva z nich vypadají jako úspěch**
/// (`exit 0`, `result` se `subtype: "success"`); jediné, co je z nich strojově čitelné, je stav
/// serveru v `init` eventu. Podrobnosti a fixtures jsou v [`docs/claude-cli.md`](../../docs/claude-cli.md).
///
/// `Codable`, protože se ukládá s osou (`ReviewerTimeline.Entry.Kind`) — po restartu má být poznat
/// totéž, co bylo poznat během běhu.
enum IntentGap: Hashable, Codable, Sendable {
    /// V konfiguraci není jméno MCP nástroje (`issueTextTool`), takže se **nic nezkoušelo**.
    ///
    /// Vlastní stav, ne „selhalo“: chybějící hodnota znamená „netahat“, ne prázdný pokus. Jméno
    /// nástroje závisí na tom, jak si uživatel pojmenoval server, takže konstanta v kódu by byla
    /// tvrzení o cizím prostředí — a session, která by se pustila naslepo, by stála peníze za nic.
    case toolNotConfigured
    /// Server, který ten nástroj nese, v session nebyl připojený.
    ///
    /// `status` je to, co hlásí `init.mcp_servers[].status` (`failed`, `needs-auth`, `pending`);
    /// `nil` znamená, že v seznamu **nebyl vůbec**. Obojí je schválně jeden případ:
    /// **nepřihlášený server je k nerozeznání od chybějícího** (server se `needs-auth` nemá
    /// v `tools` ani jednu položku) a pro toho, kdo se dívá do okna, je to tentýž stav.
    case serverUnavailable(status: String?)
    /// Nástroj se odmítl (`permission_denials`). Session doběhla `success`, takže tenhle případ je
    /// vidět jedině tady.
    case toolDenied
    /// Session doběhla, server byl připojený, ale text z odpovědi nevypadl.
    ///
    /// Sem patří i běh, kterému **chybí klíč `result`** (změřeno u `error_max_turns`) — čtení,
    /// které ho čeká jen prázdný, dostane `nil` a tvářilo by se, že odpověď přišla.
    case noAnswer
    /// Session se nepustila nebo nedoběhla — chybějící binárka, timeout.
    case sessionFailed(detail: String)
    /// Komentáře pod PR se nepodařilo přečíst, takže odkazů na zadání může být **méně**, než
    /// kolik jich pod PR je.
    ///
    /// Je to gap o **odkazech**, ne o textu, a stojí v témže výčtu schválně: pro toho, kdo se
    /// dívá, je odpověď na „dostal reviewer zadání celé?“ v obou případech `ne`. Který z nich se
    /// ukáže, když nastanou oba, rozhoduje `Policy.intentGap(text:commentsUnavailable:)`.
    case commentsUnavailable
}
