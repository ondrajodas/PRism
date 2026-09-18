import Foundation

/// Která událost notifikaci vyvolala (#86).
///
/// Notifikace si ji **nese s sebou**, takže brána nemusí hádat z textu, o co šlo. Kdyby se
/// odvozovala až u odesílání (z `ReviewState`, z místa volání), existovala by druhá cesta
/// k témuž údaji a ta by se s první rozešla — tatáž úvaha jako u `PRIdentifier`, který se
/// taky nese jako typ a ne jako text k parsování.
enum NotificationEvent: String, Codable, CaseIterable, Hashable, Sendable {
    /// Ve frontě je PR, který tam nebyl (#85).
    case newPullRequest
    /// Review dodalo nálezy — včetně běhu, který se nevešel do limitu, ale nálezy stihl.
    case findings
    /// Review doběhlo a nezbylo nic k řešení: čisto, nebo jen nálezy, které jsem odmítl.
    case clean
    /// Review se nepovedlo — spadlá session, selhaná pracovní kopie, nejistý výsledek
    /// a timeout, který **nic nenahlásil**. Timeout s nálezy patří k `findings`, protože
    /// nálezy jsou tam k přečtení; rozhoduje `Policy.reviewNotification`.
    case failure
    /// Na **vlastním** PR se ozval někdo jiný (#335) — komentář pod PR, odpověď ve vlákně,
    /// odeslané review včetně Copilotova.
    ///
    /// **Vlastní případ, ne pátý odstín výsledku review.** Zbylé čtyři jsou o naší aplikaci
    /// a o cizích PR (`Policy.reviewNotification` vlastní PR nevydá); tenhle je opačný směr —
    /// na mém PR se něco stalo bez mého přičinění. Rozhoduje `Policy.activityNotification`.
    case activity
    /// **Agent na vlastním PR doběhl** (#511) — commit v kopii repa, nic nezměnil, spadl, nebo se
    /// jeho výsledek nepřijal.
    ///
    /// **Vlastní případ, ne šestý odstín výsledku review ani druhé použití `activity`.** `activity`
    /// je „ozval se někdo jiný“, tohle je „doběhla práce, kterou jsem nespustil“ — a hlavně se to
    /// **vypíná zvlášť**: kdo si zapne agenta, nemusí chtít vyrušit u každého jeho konce, a kdo si
    /// vypne hlášky o cizích komentářích, nemá tím přijít o zprávu, že v cache leží commit.
    case agentFix
    /// **Autor odpověděl na moje review** (#523) — na cizím PR se pohnulo to, na co jsem se ptal
    /// já: commity opravily část mých komentářů, na část kolega odpověděl.
    ///
    /// **Vlastní případ, ne sedmý odstín výsledku review.** `findings`, `clean` a `failure` mluví
    /// o tom, co našel **náš reviewer**; tohle je zpráva o **cizí práci na mém review**, a hlavně
    /// se to vypíná zvlášť: kdo chce vědět, jak dopadl reviewer, nemusí chtít vyrušit u každého
    /// pushe autora — a naopak.
    case replies

    /// Co se navzájem nahrazuje, když jedna hláška ještě visí (#87).
    ///
    /// **Všechny tři výsledky review jsou jedna skupina.** Výsledek review nad PR je jeden
    /// a nový ho přepíše, ať byl předchozí jakýkoli — jinak by po opakovaném běhu zůstala
    /// vedle „3 nálezy“ viset stará hláška „reviewer nenašel žádný nález“, tedy tvrzení, které
    /// už neplatí. Chytil to test, který původně tvrdil opak.
    ///
    /// Nový PR je vlastní skupina: že PR přišel a jak dopadlo jeho review, jsou dvě různé
    /// informace a jedna nemá tu druhou přebít. **Cizí aktivita taky** (#335): že mi kolega
    /// odpověděl, nemá přebít výsledek review na tomtéž PR — jsou to dvě různé věci a obě
    /// mají zůstat na obrazovce.
    var replacementGroup: String {
        switch self {
        case .newPullRequest: "new"
        case .findings, .clean, .failure: "review"
        case .activity: "activity"
        // **Vlastní skupina.** Že doběhl agent, nemá přebít zprávu o tom, že se někdo ozval —
        // druhá z nich je zrovna ten podnět, na který ten agent reagoval, takže by se přepsala
        // příčina výsledkem.
        case .agentFix: "agent"
        // **Vlastní skupina.** Že autor opravil tři body, nemá přebít výsledek našeho reviewera
        // na tomtéž PR — jsou to dvě různé věci a obě mají zůstat na obrazovce.
        case .replies: "replies"
        }
    }
}

/// Co se má hlásit (#86).
///
/// **Jen globálně, ne per repo.** Režim i skilly se přebíjejí per repo, protože jsou to
/// vlastnosti repa — kdežto „nechci být vyrušován zprávou o čistém review“ je vlastnost
/// člověka, který se dívá. Stejná úvaha jako u `diffLayout`. Override, o který nikdo
/// nepožádal, je jen další klíč v souboru; kdyby se to ukázalo jako potřeba, je to samostatné
/// issue.
///
/// **Výchozí stav je zapnuto, u všech událostí.** Vypnuté notifikace znamenají, že se funkce
/// po vydání nikdy neprojeví — a co otravuje, se vypne jedním přepínačem. U `clean` to bylo
/// nejtěsnější rozhodnutí (je to zpráva „nemusíš nic dělat“, tedy nejmenší důvod k vyrušení),
/// ale u **ručně** spuštěného review je to zrovna ta odpověď, na kterou člověk čeká; automat
/// si ji může vypnout.
struct NotificationSettings: Codable, Equatable, Sendable {
    /// Hlavní vypínač. `false` znamená, že se **nežádá ani o oprávnění** — dialog za něco,
    /// co je vypnuté, je dialog za nic.
    var isEnabled: Bool
    var newPullRequest: Bool
    var findings: Bool
    var clean: Bool
    var failure: Bool
    /// Cizí aktivita na vlastním PR (#335). **Výchozí zapnuto** jako u zbytku: je to zpráva
    /// „někdo po tobě něco chce“, tedy ten druh vyrušení, kvůli kterému notifikace jsou.
    var activity: Bool
    /// Agent na vlastním PR doběhl (#511). **Výchozí zapnuto** jako u zbytku — a je to zpráva
    /// o práci, kterou jsem nespustil, tedy ten nejsilnější důvod dát vědět. Brána, která agenta
    /// pouští (`autoAgent`), je přitom **vypnutá**, takže nad nezapnutým agentem tenhle přepínač
    /// nic nedělá.
    var agentFix: Bool
    /// Autor odpověděl na moje review (#523). **Výchozí zapnuto** jako u zbytku: je to zpráva
    /// „druhé kolo se dá dodělat za minutu“, tedy přesně ten druh vyrušení, kvůli kterému
    /// notifikace jsou. Chodí jedině tam, kde jsem na cizím PR odeslal řádkové komentáře.
    var replies: Bool

    init(
        isEnabled: Bool = true,
        newPullRequest: Bool = true,
        findings: Bool = true,
        clean: Bool = true,
        failure: Bool = true,
        activity: Bool = true,
        agentFix: Bool = true,
        replies: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.newPullRequest = newPullRequest
        self.findings = findings
        self.clean = clean
        self.failure = failure
        self.activity = activity
        self.agentFix = agentFix
        self.replies = replies
    }

    /// Smí se tahle událost ohlásit?
    ///
    /// Hlavní vypínač přebíjí všechno — jinak by „vypnuto“ znamenalo „vypnuto, ale ještě se
    /// podívej na jednotlivé přepínače“, což je přesně to, co u vypínače nikdo neočekává.
    func allows(_ event: NotificationEvent) -> Bool {
        guard isEnabled else { return false }
        switch event {
        case .newPullRequest: return newPullRequest
        case .findings: return findings
        case .clean: return clean
        case .failure: return failure
        case .activity: return activity
        case .agentFix: return agentFix
        case .replies: return replies
        }
    }

    /// Tolerantně jako zbytek konfigurace: chybějící klíč = výchozí hodnota.
    ///
    /// Rozbitá hodnota se sráží na **výchozí (zapnuto)**, ne na vypnuto. Je to opačná volba
    /// než u `allowsPublishing`, a schválně: tam překlep nesmí otevřít cestu ven, kdežto tady
    /// je nejhorším následkem notifikace, o kterou si nikdo neřekl — a ta se dá zavřít.
    /// Umlčet aplikaci kvůli překlepu je horší, protože se to pozná až tím, že něco nepřišlo.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = NotificationSettings()
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? standard.isEnabled
        newPullRequest = (try? container.decode(Bool.self, forKey: .newPullRequest))
            ?? standard.newPullRequest
        findings = (try? container.decode(Bool.self, forKey: .findings)) ?? standard.findings
        clean = (try? container.decode(Bool.self, forKey: .clean)) ?? standard.clean
        failure = (try? container.decode(Bool.self, forKey: .failure)) ?? standard.failure
        activity = (try? container.decode(Bool.self, forKey: .activity)) ?? standard.activity
        agentFix = (try? container.decode(Bool.self, forKey: .agentFix)) ?? standard.agentFix
        replies = (try? container.decode(Bool.self, forKey: .replies)) ?? standard.replies
    }
}
