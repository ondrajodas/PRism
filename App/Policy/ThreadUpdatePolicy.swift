import Foundation

/// Zápis odeslané odpovědi, vyřešení a komentáře pod PR do už načtené konverzace.
/// Čisté funkce, žádné I/O.
///
/// Existuje proto, že #73 žádá, aby se odeslaná odpověď objevila ve vlákně **bez čekání na
/// další načtení**: GitHub v odpovědi mutace vrací celý komentář, takže není na co čekat —
/// a kolo po síti kvůli něčemu, co už máme, by v okně vypadalo jako sekání.
///
/// Vlastní soubor, ne přílepek k `ConversationPolicy`: ten odpovídá na „kam vlákno patří“,
/// tohle mění model. Dvě různé otázky.
extension Policy {
    /// Vloží odpověď na konec vlákna. `nil` = vlákno v konverzaci není.
    ///
    /// **`nil` je vlastní odpověď, ne prázdná změna.** Kdyby se vracela konverzace beze změny,
    /// odeslaná odpověď by tiše nebyla vidět a vypadalo by to, že se neodeslala — takže
    /// volající na `nil` konverzaci načte znovu. Nastává to jen tehdy, když vlákno mezitím
    /// zmizelo (obnovení, smazání na GitHubu).
    static func inserting(
        _ comment: ThreadComment,
        intoThread threadID: String,
        of conversation: Conversation
    ) -> Conversation? {
        guard conversation.threads.items.contains(where: { $0.id == threadID }) else { return nil }

        let threads = conversation.threads.items.map { thread in
            guard thread.id == threadID else { return thread }
            return thread.appending(comment)
        }
        return conversation.with(threads: threads)
    }

    /// Připíše odeslaný komentář na konec diskuze pod PR (#216).
    ///
    /// **Nevrací `nil`**, na rozdíl od odpovědi do vlákna: komentář pod PR nepatří k ničemu,
    /// co by mezitím mohlo zmizet — místo, kam se zapisuje, je konverzace sama. Není tedy stav,
    /// ve kterém by se odeslaný komentář neměl kam vložit.
    static func appending(_ comment: ThreadComment, to conversation: Conversation) -> Conversation {
        conversation.appending(comment)
    }

    /// Zapíše nový stav vyřešení i přepočítaná práva. `nil` = vlákno v konverzaci není.
    static func applying(
        _ resolution: ThreadResolution,
        to conversation: Conversation
    ) -> Conversation? {
        guard conversation.threads.items.contains(where: { $0.id == resolution.threadID })
        else { return nil }

        let threads = conversation.threads.items.map { thread in
            guard thread.id == resolution.threadID else { return thread }
            return thread.applying(resolution)
        }
        return conversation.with(threads: threads)
    }
}

private extension Conversation {
    /// Konverzace s jinými vlákny; počet i `hasNextPage` zůstávají, protože se mění **obsah**
    /// vláken, ne jejich seznam.
    ///
    /// **`events` se musí předat výslovně** (opraveno u #216): `Conversation.init` je má
    /// s výchozí prázdnou hodnotou kvůli odpovědím z doby před #171, takže vynechat je není
    /// chyba překladu — jen se osa po odeslané odpovědi tiše vyprázdnila o commity, pushe
    /// a vyžádaná review. Přesně ten druh ztráty, který v okně vypadá jako „nic tu nebylo“.
    func with(threads: [ReviewThread]) -> Conversation {
        Conversation(
            viewer: viewer,
            reviews: reviews,
            threads: ConversationPage(
                items: threads,
                total: self.threads.total,
                hasNextPage: self.threads.hasNextPage
            ),
            comments: comments,
            events: events
        )
    }

    /// Konverzace s komentářem pod PR na konci (#216).
    ///
    /// **`total` se zvyšuje s ním**, jako u odpovědi ve vlákně: bez toho by `missing`
    /// (`total − items.count`) po každém odeslaném komentáři klesl o jeden a zkrácená konverzace
    /// by tvrdila, že chybí méně, než chybí.
    func appending(_ comment: ThreadComment) -> Conversation {
        Conversation(
            viewer: viewer,
            reviews: reviews,
            threads: threads,
            comments: ConversationPage(
                items: comments.items + [comment],
                total: comments.total + 1,
                hasNextPage: comments.hasNextPage
            ),
            events: events
        )
    }
}

private extension ReviewThread {
    /// Vlákno s komentářem na konci.
    ///
    /// **`total` se zvyšuje s ním.** Bez toho by `missing` (`total − items.count`) klesl o jeden
    /// a useknuté vlákno by po každé odpovědi tvrdilo, že chybí méně — tedy přesně ten směr,
    /// proti kterému `ConversationPage` drží oba signály zkrácení. U nezkráceného vlákna by
    /// `total` navíc přestal odpovídat počtu komentářů, které v něm doopravdy jsou.
    func appending(_ comment: ThreadComment) -> ReviewThread {
        ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: originalLine,
            side: side,
            isResolved: isResolved,
            isOutdated: isOutdated,
            canResolve: canResolve,
            canUnresolve: canUnresolve,
            comments: ConversationPage(
                items: comments.items + [comment],
                total: comments.total + 1,
                hasNextPage: comments.hasNextPage
            )
        )
    }

    /// Vlákno s novým stavem vyřešení. Komentáře zůstávají — mutace o nich nic neříká.
    func applying(_ resolution: ThreadResolution) -> ReviewThread {
        ReviewThread(
            id: id,
            path: path,
            line: line,
            originalLine: originalLine,
            side: side,
            isResolved: resolution.isResolved,
            isOutdated: isOutdated,
            canResolve: resolution.canResolve,
            canUnresolve: resolution.canUnresolve,
            comments: comments
        )
    }
}
