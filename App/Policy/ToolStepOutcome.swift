import Foundation

extension Policy {
    /// Jak dopadl pokus o nástroj podle bloku `tool_result` ze `stream-json` (#326).
    ///
    /// **Rozhoduje `non_execution_kind`, ne text hlášky.** Do #326 stálo u `StreamSummary`, že
    /// odmítnutí se od chyby nástroje pozná jedině podle anglické věty
    /// (`… but you haven't granted it yet.`) a že je to křehčí, než ta informace stojí. Neplatí to:
    /// `claude` posílá u neprovedeného volání vedle bloku ještě `tool_result_meta`
    /// s `non_execution_kind` — ve fixtures `review-denied-write.jsonl` i `intent-tool-denied.jsonl`
    /// je to `user-rejected` —, takže se rozhoduje podle struktury a ne podle překladu hlášky.
    ///
    /// **`is_error` sám o sobě odmítnutí neznamená.** `grep` bez shody vrací chybu pořád a `Read`
    /// neexistujícího souboru taky; kdyby z nich byl odznak `ODMÍTNUTO`, znamenal by ten odznak
    /// „něco se nepovedlo“ místo „read-only režim zabral“ — a přesně na tom rozlišení stojí to,
    /// aby se tvrdá podmínka č. 2 nezačala vypínat.
    ///
    /// Jakýkoli **jiný** `non_execution_kind` než `user-rejected` je taky odmítnutí: znamená, že
    /// nástroj neběžel, což je tvrzení, které odznak nese. Vymýšlet čtvrtý stav pro hodnotu, kterou
    /// nikdo neviděl, by byl dohad.
    static func toolOutcome(
        isError: Bool,
        nonExecutionKind: String?,
        text: String?
    ) -> ToolAttempt.Outcome {
        if nonExecutionKind != nil {
            return ToolAttempt.Outcome(kind: .denied, reason: toolOutcomeReason(text))
        }
        guard isError else { return ToolAttempt.Outcome(kind: .passed) }
        return ToolAttempt.Outcome(kind: .failed, reason: toolOutcomeReason(text))
    }

    /// Smí nová odpověď přepsat tu, kterou krok už má? (#326)
    ///
    /// Je to **jedna funkce pro tři místa** — parser při odpovědi ze streamu, parser při záchraně
    /// z `permission_denials` a osa při zápisu do kroku. Tři kopie téhož pravidla by se rozešly,
    /// a už se to stalo: nálezem Copilota na #394 bylo, že osa přepsat nedovolila nic, takže
    /// záchrana `failed` → `denied` doputovala do souhrnu, ale do kroku, který se kreslí, ne.
    ///
    /// Platí dvě věty:
    /// - **Nezavřený krok bere cokoli.** To je běžná cesta ze streamu.
    /// - **`failed` smí přepsat jedině `denied`.** „Nemělo povolení“ je o té odpovědi silnější
    ///   tvrzení než hláška, kterou nástroj vrátil, a jedině tuhle náhradu záchrana potřebuje.
    ///
    /// Co se **nikdy** nepřepíše: `passed` (krok odpověděl, takže odmítnutý nebyl) a `denied`
    /// (o tom už je rozhodnuto — a druhá odpověď by z něj sundala odznak).
    static func replacesToolOutcome(_ current: ToolAttempt.Outcome?, with next: ToolAttempt.Outcome) -> Bool {
        guard let current else { return true }
        return current.kind == .failed && next.kind == .denied
    }

    /// Strop na hlášku, která se z odpovědi nástroje uloží.
    ///
    /// Musí být: odpovědí `Read`u je celý soubor a odpovědí `Bash`e celý výstup příkazu, takže
    /// bez stropu by jeden neúspěšný krok přilepil k záznamu na disku megabajt. Osa se přitom
    /// čte při každém startu a leží vedle nálezů.
    static let toolReasonLimit = 200

    /// Hláška z `tool_result` na jeden řádek a do stropu. `nil`, když v ní nic není — prázdný
    /// řetězec by v nápovědě kroku vypadal jako pomlčka bez důvodu.
    private static func toolOutcomeReason(_ text: String?) -> String? {
        guard let text else { return nil }
        let single = text.singleLine.trimmingCharacters(in: .whitespaces)
        guard !single.isEmpty else { return nil }
        guard single.count > toolReasonLimit else { return single }
        return String(single.prefix(toolReasonLimit)) + "…"
    }

    /// Co se u kroku v ose kreslí místo trvání (#326).
    ///
    /// Vlastní rozhodnutí, ne `if` ve view, protože jeden z těch případů je snadné splést:
    /// **pokus bez `id` se nekreslí jako běžící.** Osy uložené před #326 `id` nemají, takže se
    /// jim odpověď neměla s čím spárovat — a `běží…` u každého kroku doběhlého review z minulého
    /// týdne je text, který tvrdí víc, než data unesou.
    static func toolStepMark(of tool: ToolAttempt) -> ToolStepMark {
        guard let outcome = tool.outcome else {
            return tool.id == nil ? .none : .pending
        }
        switch outcome.kind {
        case .denied:
            return .denied
        case .passed, .failed:
            return outcome.after.map(ToolStepMark.duration) ?? .none
        }
    }
}

/// Značka na konci řádku kroku (#326).
///
/// `none` je vlastní případ, ne „nekreslit nic, když je to prázdné“: znamená **nevíme**, a to je
/// jiná odpověď než „běží“ i než „prošel za 0,2 s“.
enum ToolStepMark: Equatable, Sendable {
    case none
    case pending
    case duration(Duration)
    case denied
}
