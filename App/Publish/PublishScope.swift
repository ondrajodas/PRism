import Foundation

/// Kam se **smí** odeslat review.
///
/// **Jediné místo, které na tu otázku odpovídá** — ptá se ho `GhReviewPublisher.submit`
/// (první kontrola v cestě, ještě před sítí) i `Policy.sendBlock`, aby okno hlásilo tentýž
/// důvod, na kterém odeslání doopravdy skončí. Dvě místa, kde se to vyhodnocuje, by se
/// rozešla.
///
/// **Od #107 se skládá z konfigurace, ne ze zadrátovaného seznamu.** Do té doby tu stála
/// množina s jediným sandboxem a odůvodnění, že brána v `config.json` už není brána, ale
/// nastavení. Změnilo se to proto, že „kam smím odesílat“ je rozhodnutí **per repo**, které
/// se mění často — a jako konstanta stálo každé takové rozhodnutí commit, review a release,
/// tedy cenu, kterou má platit změna *pravidla*, ne změna *jednoho repa*. Proti omylem
/// odeslanému review nechrání seznam, ale potvrzení s úplným výpisem payloadu (#68)
/// a pre-flight na `headSha` (#67); ty se nemění.
///
/// Vlastnost „samo nic neodejde“ drží **výchozí stav vypnuto** (`GlobalConfig.allowsPublishing`
/// je `false`): dokud si někdo výslovně neřekne o konkrétní repo nebo neotočí globální
/// default, nejde odeslat nikam. Sandbox v tom **není výjimka** — zapíná se stejným
/// přepínačem jako cokoli jiného, protože výjimka v kódu by tvrdila něco jiného než nastavení.
struct PublishScope: Sendable, Equatable {
    private let configuration: Configuration

    /// Snímek konfigurace, ne odkaz na store: scope se skládá **při kliknutí**
    /// (`AppStore.submission(for:)`), takže přepnutí v nastavení platí bez restartu — a co je
    /// vidět v potvrzení, to platí i při odeslání.
    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func allows(_ repo: RepoID) -> Bool {
        configuration.resolved(for: repo).allowsPublishing
    }
}
