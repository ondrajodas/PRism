import Foundation

/// Razítko předání zadání agentovi (#334) — **kdy, proti jaké hlavě a co v něm bylo**.
///
/// Bydlí u pull requestu, ne u promptu: `AgentPrompt` zaniká zavřením sheetu, kdežto „předáno
/// v 14:20 proti 9c1de02“ musí přežít restart. Je to tatáž součástka jako `againstHeadSha`
/// u kontroly nálezů (#150), jen se ptá na něco jiného — ta se ptá „na co jsem se ptal“, tohle
/// „co jsem už poslal“. Proto taky nebydlí u nálezů, ale u PR: předat se dá i zadání, ve kterém
/// není jediný nález (vlákno od kolegy, komentář pod PR), a takové PR nemá uložený záznam vůbec.
///
/// **Samotný čas nestačí.** Bez hlavy by panel tvrdil „předáno“ i po deseti pushích — nálezy
/// jsou klíčované `headSha` (tvrdá podmínka č. 5), takže po pushi mluví předané zadání o kódu,
/// který na PR není. Teprve dvojice `(kdy, proti čemu)` dovolí odpovědět, jestli ještě platí.
struct Handoff: Hashable, Codable, Sendable {
    /// Kdy se zadání předalo — tedy kdy si ho člověk zkopíroval nebo uložil do souboru.
    /// Otevření sheetu předání **není**: text, který nikdo nevzal, nikam nedošel.
    let at: Date
    /// Hlava PR v době předání. `nil` = detail se v tu chvíli ještě nenačetl, takže se platnost
    /// zadání nedá potvrdit ani vyvrátit — a text promptu to o sobě říká nahlas.
    let headSha: String?
    /// Identity předaných položek (`AgentPromptItem.id`) — **všech, co kdy odešly**, ne jen těch
    /// z posledního textu.
    ///
    /// Sčítá je `AppStore.noteHandoff(of:)`, a je to kvůli zúženému zadání po pushi: to nese jen
    /// novou diskuzi, takže by přepsané razítko udělalo z dřív předaných nálezů „nepředané“
    /// a odznak by se rozsvítil za práci, která odešla.
    ///
    /// **Ne jen počet.** Počet by odpověděl na „kolik jsem poslal“, ale ne na „co zbývá“:
    /// zadání se dá sestavit s vypnutou volbou, takže nevyřešené vlákno může zůstat mimo text —
    /// a razítko s počtem by ho odepsalo jako předané. S identitami je odpověď přesná a bere
    /// v úvahu i to, že se nálezy mezitím přepočítají: týž nález má týž klíč
    /// (`Policy.key(of:)`), takže opakované review nálezem znovu nezasvítí, kdežto **nový**
    /// nález ano.
    let handed: Set<String>

    init(at: Date, headSha: String?, handed: Set<String>) {
        self.at = at
        self.headSha = headSha
        self.handed = handed
    }

    /// Kolik položek je předaných — do popisku `✓ 6 položek`. Je to velikost `handed`, tedy součet
    /// přes všechna předání, ne délka posledního textu.
    var count: Int { handed.count }

    /// Zkrácená hlava do textu — sedm znaků, jak ji píše `git`. Stejně jako
    /// `AgentPromptSubject.shortHead`, protože je to tentýž údaj na téže obrazovce.
    var shortHead: String? {
        guard let headSha, !headSha.isEmpty else { return nil }
        return String(headSha.prefix(7))
    }

    /// Byla tahle položka v předaném zadání?
    func includes(_ id: String) -> Bool { handed.contains(id) }

    /// Dekóduje a kóduje se ručně **jen kvůli `handed`**: množina se do JSONu ukládá jako pole
    /// v nahodilém pořadí, takže by se soubor přepisoval i tehdy, když se nic nezměnilo. Pole je
    /// proto **řazené** — je to tatáž úvaha jako u snímku ohlášených PR.
    /// Vyjmenované ručně: obě strany `Codable` jsou vlastní, takže se `CodingKeys` nesyntetizují.
    private enum CodingKeys: String, CodingKey {
        case at
        case headSha
        case handed
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decode(Date.self, forKey: .at)
        headSha = try container.decodeIfPresent(String.self, forKey: .headSha)
        handed = Set(try container.decode([String].self, forKey: .handed))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(at, forKey: .at)
        try container.encodeIfPresent(headSha, forKey: .headSha)
        try container.encode(handed.sorted(), forKey: .handed)
    }
}
