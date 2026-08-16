import Foundation

/// Časový limit jednoho běhu revieweera (#320) — výchozí hodnota a **meze i s důvodem**.
///
/// Do #320 byl limit zadrátovaný (`ClaudeReviewRunner.defaultTimeout`, patnáct minut), takže se
/// dal zvednout jedině přeložením aplikace — a přitom `docs/architektura.md` u rozlišení
/// `timedOut` proti `interrupted` už tehdy tvrdila, že „timeout říká, že je review pomalé (dá se
/// zvednout limit)“. Ta věta byla slib, který uživatel neměl jak uplatnit.
///
/// **Meze jsou bezpečnostní, ne kosmetické.** Timeout je jediná pojistka proti session, která se
/// zacyklí a utrácí peníze — všechno ostatní (`autoRunsPerDay`, `maxConcurrentReviews`) omezuje
/// **počet** běhů, ne délku jednoho. „Bez limitu“ proto **není volba**: neexistuje hodnota, kterou
/// by šlo napsat a která by hlídání vypnula, a co je mimo rozsah, se sráží dovnitř.
enum ReviewTimeout {
    /// Patnáct minut — **doslova to, co bylo do #320 v kódu**. Zavedení nastavení nesmí změnit
    /// chování; hlídá to test, který porovnává hodnotu, ne odkaz na tuhle konstantu.
    static let standardMinutes = 15

    /// Dolní mez **5 minut**.
    ///
    /// Změřeno na 19 bězích s vyplněnou dobou trvání z provozní cache: medián **2,5 min**,
    /// nejdelší doběhlý běh **6,8 min**, čtvrtina běhů nad 3 min. Pod pěti minutami by limit řezal
    /// doprostřed pásma, ve kterém běžné review žije — `timedOut` by přestal být zprávou o pomalém
    /// review a stal se vlastností nastavení, tedy tou „poruchou aplikace“, které se issue bojí.
    ///
    /// Níž to nemá ani proč jít: **zkrácení limitu nešetří peníze**. Zabitá session už utratila,
    /// co utratila, a místo hotových nálezů z ní zbydou částečné. Jediný důvod limit snižovat je
    /// netrpělivost, a na tu stačí tlačítko `Zrušit`.
    static let minimumMinutes = 5

    /// Horní mez **60 minut**, a vazba na rozpočet je přímá: strop krát `autoRunsPerDay` je
    /// nejhorší možný den na účtu.
    ///
    /// S výchozími 20 automatickými běhy denně je při 15 minutách strop pět hodin session za den,
    /// při 60 minutách dvacet. Naměřený běžný běh stojí zhruba **0,40 $/min** (medián 1,05 $ za
    /// 2,5 min) a session, která se utrhne, násobky toho — v cache leží běh za **14,67 $ pod
    /// minutou**, takže peníze nejsou funkcí času, ale hodina navíc je pořád hodina, ve které se
    /// utrácí bez dozoru. Šedesát minut je poslední hodnota, u které se dá mluvit o pojistce; nad
    /// ní už limit nechrání před ničím a rovnalo by se to „bez limitu“.
    static let maximumMinutes = 60

    /// Co se dá nastavit. Rozsah, ne dvě volné konstanty — pole v nastavení i sráření hodnoty ze
    /// souboru musí mluvit o týchž mezích.
    static let allowedMinutes = minimumMinutes...maximumMinutes

    /// Výchozí limit jako `Duration`. Kvůli požadavkům v testech, které o konfiguraci nic nevědí.
    static let standard = Duration.seconds(standardMinutes * 60)

    /// Hodnota v konfiguraci je mimo meze.
    ///
    /// Vlastní typ, ne `Bool` — stejně jako `ReviewPromptTemplate.Problem`: text u pole má říct
    /// **kolik je v souboru**, **s čím se doopravdy poběží** a **proč mez existuje**. Spolknout to
    /// by znamenalo, že si někdo napíše 120 minut, poběží se s 60 a nic to neřekne.
    enum Problem: Hashable, Sendable {
        /// Kratší než dolní mez.
        case tooShort(configured: Int)
        /// Delší než horní mez.
        case tooLong(configured: Int)

        /// Co je napsané v konfiguraci.
        var configured: Int {
            switch self {
            case .tooShort(let configured), .tooLong(let configured): configured
            }
        }

        /// S čím se doopravdy poběží.
        ///
        /// Počítá se **tímtéž sráření**, kterým hodnota projde na cestě do běhu — ne vypsanou
        /// mezí. Dvě místa by se rozešla a hláška by slibovala jiné číslo, než jaké by platilo.
        var applied: Int { Policy.reviewTimeoutMinutes(from: configured) }

        /// Proč to vadí. Bez důvodu je hláška „mimo rozsah“ jen zákaz.
        var reason: String {
            switch self {
            case .tooShort:
                "V konfiguraci je \(configured) min, běží se s \(applied) min."
                    + " Kratší limit dělá timeout i z review, které fungovalo — nejdelší naměřený"
                    + " doběhlý běh trval 6,8 min."
            case .tooLong:
                "V konfiguraci je \(configured) min, běží se s \(applied) min."
                    + " Limit je jediná pojistka proti zacyklené session, takže strop má —"
                    + " „bez limitu“ nastavit nejde."
            }
        }
    }
}

extension Policy {
    /// Limit, se kterým se doopravdy poběží. Co je mimo meze, se **srazí dovnitř**, ne odmítne.
    ///
    /// Sráží se schválně a je to tatáž volba jako u ostatních čísel v nastavení (interval
    /// pollingu, rozpočet cache): rozbitá hodnota nesmí položit čtení celé konfigurace, protože
    /// soubor se edituje ručně a jedno číslo navíc by pak sebralo zdroje PR i skilly. Že se srazilo,
    /// **není potichu** — `reviewTimeoutProblem(in:)` to pojmenuje pod polem v nastavení.
    static func reviewTimeout(minutes configured: Int) -> Duration {
        .seconds(reviewTimeoutMinutes(from: configured) * 60)
    }

    /// Kolik minut z konfigurované hodnoty vyjde — **jediné sráření v aplikaci**.
    ///
    /// Zvlášť od `reviewTimeout(minutes:)` proto, že v minutách se to musí umět říct i mimo běh:
    /// hláška u pole v nastavení (`ReviewTimeout.Problem.applied`) mluví o minutách a musí slibovat
    /// tutéž hodnotu, jaká pak doopravdy platí.
    static func reviewTimeoutMinutes(from configured: Int) -> Int {
        min(
            max(configured, ReviewTimeout.allowedMinutes.lowerBound),
            ReviewTimeout.allowedMinutes.upperBound
        )
    }

    /// Co je na konfigurované hodnotě špatně. `nil` = v mezích, tedy není o čem mluvit.
    static func reviewTimeoutProblem(in configured: Int) -> ReviewTimeout.Problem? {
        if configured < ReviewTimeout.allowedMinutes.lowerBound {
            return .tooShort(configured: configured)
        }
        if configured > ReviewTimeout.allowedMinutes.upperBound {
            return .tooLong(configured: configured)
        }
        return nil
    }
}
