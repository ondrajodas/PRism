import Foundation

/// Které komentáře pod PR jsou **moje** a na kterých z nich má co říkat model (#522).
///
/// Dvě funkce, dvě různé otázky. `sentComments(in:)` je **celý** seznam, o kterém druhé kolo
/// mluví; `unansweredComments(in:)` je jeho podmnožina, na kterou se ptá session. Že se liší,
/// je to podstatné: **model se ptá jedině tam, kde data mlčí**. Vlákno s odpovědí zná konverzace
/// (#72), takže verdikt o něm by byl tvrzení navíc — a to by aplikace v okně nakonec ukázala.
extension Policy {
    /// Moje odeslaná vlákna, v pořadí, v jakém konverzace přišla.
    ///
    /// **Moje = vlákno jsem založil**, tedy první komentář je můj. Odpověď do cizího vlákna mě
    /// autorem nedělá: druhé kolo je o tom, na co jsem se ptal já, a cizí vlákno, do kterého jsem
    /// se přidal, čte člověk jako součást té cizí diskuze.
    ///
    /// **Vyřešená vlákna se neodečítají.** Vyřešit smí kdokoli a o kódu to neříká nic — odečíst
    /// je tady by znamenalo, že komentář zmizí z druhého kola kliknutím, ne opravou. Kdo je při
    /// kresbě nechce (#523), si je odfiltruje sám; ztratit se v datech nesmí.
    ///
    /// Vlákno **bez komentářů** se přeskakuje: nemá text, kterým bych se ptal, ani autora, ze
    /// kterého by se poznalo, čí je.
    static func sentComments(in conversation: Conversation?) -> [SentComment] {
        guard let conversation else { return [] }
        return conversation.threads.items.compactMap { thread in
            guard let opener = thread.comments.items.first, conversation.isMine(opener) else {
                return nil
            }
            return SentComment(
                threadID: thread.id,
                path: thread.path,
                // Zastaralé vlákno si nese původní číslo — bez něj by komentář v promptu neměl
                // kotvu a session by ho hledala v celém souboru.
                line: thread.anchorLine,
                body: opener.body
            )
        }
    }

    /// Moje vlákna, do kterých **nikdo neodpověděl** — tedy ta, na která se session ptá.
    ///
    /// Hranice mezi daty a modelem se drží **už ve vstupu**, ne až v zobrazení: verdikt, který by
    /// se stejně nikdy neukázal (odpověď z dat má přednost), by ležel uložený a čekal, až ho
    /// někdo omylem přečte. Vedlejší efekt je, že se za něj neplatí.
    static func unansweredComments(in conversation: Conversation?) -> [SentComment] {
        guard let conversation else { return [] }
        let answered = answeredThreadIDs(in: conversation)
        return sentComments(in: conversation).filter { !answered.contains($0.threadID) }
    }

    /// Identity **mých** vláken, ve kterých je odpověď někoho jiného.
    ///
    /// Počítá se **kdokoli kromě mě**, ne jen autor PR: na PR chodí i třetí lidi a Copilot, a
    /// „někdo mi odpověděl“ je pro druhé kolo tatáž informace. Moje vlastní další příspěvky se
    /// nepočítají — že jsem si odpověděl sám, není odpověď (tatáž úvaha jako u cizí aktivity
    /// #335).
    ///
    /// Cizí vlákna se do množiny nedostanou vůbec, i když v nich odpověď je: byla by to identita,
    /// kterou nikdo nečte, protože do druhého kola takové vlákno nepatří.
    static func answeredThreadIDs(in conversation: Conversation) -> Set<String> {
        var answered: Set<String> = []
        for thread in conversation.threads.items {
            guard let opener = thread.comments.items.first, conversation.isMine(opener) else {
                continue
            }
            if thread.comments.items.contains(where: { !conversation.isMine($0) }) {
                answered.insert(thread.id)
            }
        }
        return answered
    }
}
