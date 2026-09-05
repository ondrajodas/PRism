import Foundation

/// Odložený pull request (#512) — *tenhle teď vidět nechci, ozvi se mi, až…*.
///
/// **Ukládá se k PR, ne k `headSha`, a je to zapsaná volba proti tvrdé podmínce č. 5.** Ta mluví
/// o **nálezech**: tvrzení o kódu se nesmí ukazovat proti kódu, který už neexistuje. Odložení
/// o kódu netvrdí nic — je to moje rozhodnutí o tom, kdy se na PR podívám, a push ho nemá
/// zneplatnit, nýbrž **splnit** (`SnoozeCondition.nextPush`). Precedens je rozhovor nad PR (#452),
/// který se z téhož důvodu ukládá k PR. Hlava v tom přesto figuruje, jen v opačné roli: je to
/// **měřidlo podmínky**, ne klíč záznamu.
struct Snooze: Codable, Hashable, Sendable {
    let pullRequest: PRIdentifier
    /// Za jakých okolností se PR vrátí. **Proměnná**, protože se v ní usazuje výchozí hodnota
    /// měřidla — viz `SnoozeCondition`.
    var condition: SnoozeCondition
    /// Kdy jsem ho odložil. Do bloku `Odložené` se nekreslí; je to údaj pro rozhodnutí, jestli
    /// odložení nesedí v cache po PR, který se dávno zavřel (`SnoozeStore.retention`).
    let since: Date
}

/// Za čeho odložení skončí (#512).
///
/// **Podmínka, ne jen čas** — to je celé zadání. „Do zítra“ a „na týden“ jsou tentýž případ
/// s jiným datem; „do dalšího pushe“ a „do dalšího komentáře“ se měří proti hodnotě, kterou PR
/// nesl ve chvíli odložení.
///
/// **Měřidlo je volitelné a je to bezpečná strana, ne nedodělek.** Ve chvíli odložení hlavu ani
/// počet příspěvků obvykle neznáme: fronta stojí na `gh search prs`, které ani jedno nevrací,
/// a detail se tahá až při otevření PR. `nil` proto znamená *ještě nevím, od čeho měřit* a
/// `Policy.snoozeExpired` z něj **nikdy** neudělá „vypršelo“ — základ doplní první rozhlídka
/// (`Policy.snoozeBaseline`). Opačná volba (neznámé měřidlo = vrátit hned) by odložení zrušila
/// dřív, než by se stihlo projevit, tedy přesně to, co má být na téhle věci nejspolehlivější.
enum SnoozeCondition: Codable, Hashable, Sendable {
    /// Do daného okamžiku. `do zítra 9:00`, `na týden`, `Vlastní datum…`.
    case until(Date)
    /// Do dalšího pushe. Měřidlem je **hlava PR** ve chvíli odložení.
    case nextPush(head: String?)
    /// Do dalšího komentáře. Měřidlem je **počet příspěvků** pod PR ve chvíli odložení; co se do
    /// něj počítá, je v `SnoozeSignal.comments`.
    case nextComment(count: Int?)

    /// Potřebuje tahle podmínka odpověď z GitHubu, aby se dala vyhodnotit?
    ///
    /// Čas ne — ten se pozná z hodin. Rozhoduje o tom, koho se rozhlídka ptá
    /// (`Policy.snoozeProbe`): dotaz na PR odložený do zítřejšího rána by byl dotaz za nic.
    var needsSignal: Bool {
        switch self {
        case .until: false
        case .nextPush, .nextComment: true
        }
    }
}

/// Co PR z odložení vrátilo (#512) — do řádku dění a do věty pod ním.
///
/// **Vlastní výčet, ne `SnoozeCondition`**: `Vrátit teď` žádnou podmínkou není a přesto je to
/// nejčastější způsob návratu. Kdyby se důvod odvozoval z podmínky, musel by se ruční návrat
/// tvářit jako splněná podmínka, kterou nikdo nesplnil.
enum SnoozeReturn: Hashable, Sendable {
    case time
    case push
    case comment
    /// `Vrátit teď` v bloku `Odložené`.
    case manual
}

/// Co se na odloženém PR změřilo (#512) — hlava a počet příspěvků, jedním dávkovým dotazem.
///
/// **Vlastní model vedle `PullRequestHead`, ne jeho rozšíření.** `PullRequestHead` je odpověď na
/// jednu otázku (kde PR stojí) a čte ji rozhlídka po zastaralých nálezech; přidat do něj počet
/// komentářů by znamenalo typ, jehož jméno mluví o hlavě a jehož polovinu ta rozhlídka nikdy
/// nepřečte. Dva modely stojí dvě volání za tik **v nejhorším případě** — a oba mají předfiltr
/// přes `updatedAt`, takže na klidný den je to nula.
struct SnoozeSignal: Hashable, Sendable {
    /// Sha, na které PR stojí teď.
    let head: String
    /// Kolik příspěvků pod PR GitHub napočítal: **komentáře pod pull requestem plus odeslaná
    /// review**. Odpověď ve vlákně u kódu je v GitHubu review o jednom komentáři, takže se počítá
    /// taky; naopak úprava titulku, štítek ani nový commit počet nezvednou — a právě proto se
    /// „do dalšího komentáře“ neměří přes `updatedAt`, které se hýbe po všem.
    let comments: Int
}
