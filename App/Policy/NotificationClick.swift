import Foundation

/// Co udělat s klikem na notifikaci (#409).
///
/// **Vlastní typ, ne dva booleany u volajícího.** Rozhodnutí se skládá ze tří vstupů (je PR
/// v seznamu, je vidět po filtru, načetl se už seznam) a vede ke třem různým následkům, z nichž
/// dva jsou vratné jen ručně (zrušený filtr, otevřená záložka). Než aby to obsluha proudu
/// skládala `if`em, vrací se hodnota, kterou jde vyjmenovat v testu — a právě to u #409 chybělo:
/// obsluha nastavovala `selection`, testy tvrdily `selection`, a nikdo nekontroloval, že se
/// v okně **něco stalo**.
enum NotificationClick: Equatable, Sendable {
    /// Nic. PR ze seznamu zmizel (mergnul se, review už po mně nikdo nechce), takže není co
    /// otevřít — a skočit místo toho jinam je horší než nechat na obrazovce to, co tam bylo.
    case ignore
    /// Otevřít záložku toho PR. `clearsFilter` = schoval ho filtr (#117), takže se filtr ruší.
    case open(clearsFilter: Bool)
}

extension Policy {
    /// Co udělat s klikem na notifikaci (#409). Rozhodnutí, ne provedení — filtr ruší a záložku
    /// otevírá `AppStore`.
    ///
    /// Tři vstupy a tři rozhodnutí:
    ///
    /// 1. **PR v seznamu se otevře.** Klik na notifikaci je výslovná žádost tenhle PR vidět,
    ///    a od #180 to znamená **záložku**, ne výběr řádku — viz `AppStore.openTab(_:in:)`.
    /// 2. **PR mimo seznam se neotevírá naslepo.** Notifikace přežije tik, který ho odklidil, takže
    ///    `pullRequests` je odpověď na „existuje ještě“. Výjimka je stav, kdy se seznam **ještě
    ///    nenačetl** (`notStarted`): aplikaci spustilo právě tohle kliknutí, takže prázdný seznam
    ///    neznamená „PR je zavřený“, ale „ještě nevím“ — a zahodit ten klik by rozbilo zrovna ten
    ///    scénář, kvůli kterému má proud kliknutí buffer.
    /// 3. **Filtr, který PR schoval, se ruší.** Ptá se na to, co je vidět **po filtru**, ne na
    ///    fronty rozřazené podle autora: vlastní PR (#331) je pořád PR, který se dá otevřít, takže
    ///    by z rozřazení vyšlo zahození kliknutí za nic.
    ///
    /// **Plný seznam a jeho zúžená podoba jdou dovnitř jako dva parametry**, ne jako seznam plus
    /// filtr: rozhodnutí, jestli PR projde filtrem, závisí na uložených nálezech
    /// (`AppStore.passesFilter`), a druhé místo, které si ho skládá, by se s prvním rozešlo (#371).
    static func notificationClick(
        on pr: PRIdentifier,
        listed: [PullRequestSummary],
        visible: [PullRequestSummary],
        status: PollStatus
    ) -> NotificationClick {
        guard listed.contains(where: { $0.id == pr }) else {
            // Dokud se seznam nenačetl, filtr nemá co schovávat — schovat může jedině řádek,
            // který dorazil.
            return status == .notStarted ? .open(clearsFilter: false) : .ignore
        }
        return .open(clearsFilter: !visible.contains { $0.id == pr })
    }
}
