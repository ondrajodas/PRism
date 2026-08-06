import Foundation

/// Co jeden běh review stál — cena, trvání a počet kol modelu (#148).
///
/// Všechna tři pole jsou **volitelná a `nil` neznamená nulu**. Hodnoty nese `result` event
/// ze `stream-json` a ten **zabitý běh nemá vůbec** (je na to fixture `review-killed.jsonl`),
/// takže nula by tvrdila, že běh byl zdarma — a to je zrovna ten druh tichého tvrzení, kterému
/// se aplikace u nálezů vyhýbá. Totéž platí o běhu dotaženém z transcriptu (#97): ten `result`
/// nemá taky.
///
/// Na disku je tvar **vlastní**, ne syntetizovaný: `Duration` se `Codable`m kóduje jako dvojice
/// celých čísel int128, což je v souboru, do kterého se dá kouknout, nečitelné. Klíče proto
/// nesou jednotku (`costUSD`, `durationMS`) — tatáž úvaha jako u identifikátorů kódovaných na
/// jediný řetězec.
struct RunUsage: Codable, Hashable, Sendable {
    /// `total_cost_usd`. V dolarech, protože v nich to `claude` hlásí; přepočet by znamenal
    /// držet kurz.
    var cost: Double?
    /// `duration_ms` — celé trvání běhu, ne jen čas strávený v API (`duration_api_ms`).
    var duration: Duration?
    /// `num_turns` — kolik kol si session vyžádala.
    var turns: Int?

    /// Nemá smysl ji držet, když v ní nic není. Rozhoduje o tom `StreamParser`, aby
    /// `summary.usage == nil` znamenalo „nevíme nic“ a ne „máme prázdný obal“.
    var isEmpty: Bool {
        cost == nil && duration == nil && turns == nil
    }

    init(cost: Double? = nil, duration: Duration? = nil, turns: Int? = nil) {
        self.cost = cost
        self.duration = duration
        self.turns = turns
    }

    private enum CodingKeys: String, CodingKey {
        case costUSD
        case durationMS
        case turns
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cost = try container.decodeIfPresent(Double.self, forKey: .costUSD)
        duration = try container.decodeIfPresent(Int.self, forKey: .durationMS).map(Duration.milliseconds)
        turns = try container.decodeIfPresent(Int.self, forKey: .turns)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cost, forKey: .costUSD)
        try container.encodeIfPresent(duration.map { $0.milliseconds }, forKey: .durationMS)
        try container.encodeIfPresent(turns, forKey: .turns)
    }
}

extension Duration {
    /// Celé milisekundy. Zaokrouhlené dolů, protože `duration_ms` v milisekundách přišlo —
    /// zpátky se tedy nic neztrácí.
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

/// Kolik dnešek stál — součet za všechny běhy, které dneska skončily (#148).
///
/// **Drží `unknown`**, tedy počet běhů, které cenu nenahlásily. Bez něj by se součet po
/// zabitém běhu tvářil jako úplný, přitom zabitá session peníze stála a jen o nich nevíme;
/// je to totéž pravidlo jako u `droppedFindings` a `ConversationPage.isTruncated` — utnutá
/// data nesmí vypadat jako úplná.
struct DailySpend: Codable, Hashable, Sendable {
    /// Součet v dolarech.
    var cost = 0.0
    /// Kolik běhů se do součtu započítalo.
    var runs = 0
    /// Kolik běhů skončilo bez ceny. Součet je pak **dolní odhad**.
    var unknown = 0

    var isEmpty: Bool {
        runs == 0 && unknown == 0
    }
}
