import Foundation

/// Co se na pull requestu **stalo** — položka časové osy z GitHubu (#171).
///
/// Je to třetí druh cizího obsahu vedle review a komentářů, a schválně vlastní typ: review
/// je něčí názor, komentář něčí věta, kdežto tohle je záznam děje („pushnul“, „vyžádal
/// review“, „mergnul“). Slít je do `ThreadComment` by znamenalo vymýšlet tělo komentáře
/// tomu, kdo nic nenapsal.
///
/// Nepersistuje se, jako celá `Conversation` — `Codable` je kvůli konvenci modelů a testům
/// round-tripu, ne kvůli disku.
struct TimelineEvent: Hashable, Codable, Sendable, Identifiable {
    /// `id` uzlu z GraphQL, ne pořadí ani obsah.
    ///
    /// Bere se přes `... on Node { id }` — jedno pole místo deseti fragmentů (ověřeno na
    /// živém API: 29 z 29 položek `cli/cli#13084` ho má a jsou unikátní). Skládat identitu
    /// z druhu a času nejde: na PR běžně stojí za sebou několik shodných párů „vyžádal
    /// review / odebral“ a při shodě na sekundu by je `ForEach` slil do jedné.
    let id: String
    let kind: Kind
    /// Kdo za tím stojí. `nil` = GitHub actora nevrátil (smazaný účet, systémová akce).
    let actor: EventActor?
    /// Kdy se to stalo. `nil` = nevíme, tedy stejná úmluva jako u `ConversationEntry.date`.
    ///
    /// **U commitu je to datum commitu, ne pushnutí.** `PullRequestCommit` nic jiného
    /// nenabízí — `pushedDate` GitHub už neplní (změřeno: `null` u všech 21 commitů
    /// `cli/cli#13084`), takže po rebase nebo merge cizí větve umí commit sedět jinde, než
    /// kde ho ukazuje GitHub. Vědomé omezení, viz specifikace.
    let at: Date?

    init(id: String, kind: Kind, actor: EventActor?, at: Date?) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.at = at
    }

    /// Druh události. Uzavřený výčet, i když GitHub jich má desítky — bere se jen to, co se
    /// při review hodí vědět, a co dotaz vyjmenuje v `itemTypes`.
    enum Kind: Hashable, Codable, Sendable {
        /// Pushnutý commit. `oid` je celý sha, krátí se až při zobrazení.
        case commit(oid: String, headline: String)
        /// Vyžádané review. `reviewer` je `nil`, když ho GitHub nevrátil — změřeno na
        /// `cli/cli#13084`, kde u jedné události přišel `requestedReviewer: null`. Událost se
        /// kvůli tomu **nezahazuje**: „někdo si vyžádal review“ je pořád informace.
        case reviewRequested(reviewer: String?)
        case reviewRequestRemoved(reviewer: String?)
        /// Přepsaná historie větve. Tohle je ta událost, po které zastarají nálezy i draft.
        case forcePushed(before: String?, after: String?)
        case readyForReview
        case convertedToDraft
        case merged(into: String?)
        case closed
        case reopened
        case baseChanged(from: String?, to: String?)
    }

    /// Vyžádal si někdo review **sám od sebe**?
    ///
    /// GitHub to píše jinou větou („self-requested a review“), takže se to musí dát poznat —
    /// a pozná se to tady, ne v textu ve view: je to vztah mezi dvěma poli události, ne
    /// otázka vykreslení. Bez aktéra nebo bez cíle se to tvrdit nedá.
    var isSelfDirected: Bool {
        guard let actor else { return false }
        return switch kind {
        case .reviewRequested(let reviewer), .reviewRequestRemoved(let reviewer):
            reviewer == actor.login
        default: false
        }
    }
}

/// Kdo stojí za událostí — jméno, obrázek a jestli je to bot.
///
/// Vlastní typ, ne `String`: k události patří avatar, a `Conversation.viewer` se s ním
/// porovnávat nemá (na rozdíl od komentářů se u „pushnul commit“ neptáme, jestli je můj).
struct EventActor: Hashable, Codable, Sendable {
    let login: String
    /// Adresa obrázku ve velikosti, o kterou si řekl dotaz. `nil` = GitHub ji nevrátil
    /// (commit s e-mailem, který nesedí na účet).
    let avatarURL: URL?
    /// Bot se v okně označuje, jako to dělá GitHub — `github-actions` vyžádá review stejně
    /// jako člověk a splést si je znamená hledat, kdo to udělal.
    let isBot: Bool

    init(login: String, avatarURL: URL?, isBot: Bool) {
        self.login = login
        self.avatarURL = avatarURL
        self.isBot = isBot
    }
}
