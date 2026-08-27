import Foundation

/// **Jediná cesta, kterou z aplikace něco odejde na GitHub.**
///
/// Do #67 to vynucoval typ: `GitHubGateway` schválně neměl metodu, kterou by šlo něco
/// odeslat. Ta vlastnost **zůstává** — zápis dostal vlastní modul, takže polling, diff,
/// checkout ani reviewer nemají čím něco poslat. `grep ReviewPublishing App/` vyjmenuje všechna
/// místa, odkud to jde: **sedm souborů a pět volajících** — protokol, `GhReviewPublisher`,
/// `ReviewSubmission`, `ThreadSubmission`, `CommentSubmission`, `MetadataSubmission`
/// a `MergeSubmission`. Roste-li
/// ten výčet, roste to, co aplikace umí odeslat, a to musí být vidět z jednoho grepu.
///
/// Metody jsou **vyjmenované a je jich osm** (do #73 jedna, do #216 tři, do #392 čtyři, do #413
/// šest, do #465 sedm). Každá
/// odpovídá jedné věci, kterou člověk v okně udělá — odeslat review, odpovědět do vlákna,
/// přepnout jeho vyřešení, napsat komentář pod PR, přeštítkovat svůj PR, vyžádat na něm review,
/// založit label, který repozitář ještě nezná, mergnout vlastní PR.
/// Co tady být **nesmí**: approve mimo review, **zavření PR**, **milník** a **smazání
/// labelu**. Roste-li
/// tenhle výčet, roste to, co aplikace umí odeslat, a to má být vidět v jednom souboru.
///
/// **Komentář pod PR přibyl u #216** a je to vědomé rozšíření tvrdé podmínky č. 1, ne její
/// obejití. Důvod je tentýž jako u odpovědi do vlákna: konverzace pod PR je v okně vidět celá,
/// takže napsat do ní jednu větu je poslední věc, kvůli které se odsud přepíná do prohlížeče.
/// Co se **nezměnilo**: výčet je pořád krátký a na jednom místě, každá metoda si sama ověří
/// bránu, a `GitHubGateway` zápis dál nemá.
///
/// **Labely a vyžádání reviewera přibyly u #392** — pátá a šestá metoda, a je to vědomá změna
/// pravidla: do té doby tady stálo, že „label ani zavření PR sem nepatří“. Změnilo se to proto, že
/// štítek a reviewer jsou u **vlastního** PR součástí toho, jak si člověk řídí svoji frontu, a je
/// to poslední věc, kvůli které se od hotového review přepíná do prohlížeče. Tentýž precedens
/// i tatáž úvaha jako u #73 a #216: výčet se rozšířil, protože se ta věc dělá při review,
/// a **zapsal se důvod**. Co se **nezměnilo**: brána je tatáž (`PublishScope`, `allowsPublishing`
/// globálně i per repo — žádný druhý přepínač), výčet je krátký a na jednom místě, `GitHubGateway`
/// zápis dál nemá a **v zákazu zůstává** approve mimo review, merge, zavření PR a milník.
///
/// **Založení labelu přibylo u #413** — sedmá metoda a **první, která zapisuje do repozitáře, ne do
/// pull requestu**. Do té doby všech šest sahalo na PR nebo na diskuzi, tedy na věc, která je vratná
/// jedním klikem nebo která se zavřením PR přestane týkat čehokoli dalšího; label vzniklý omylem
/// **zůstane v repu navždycky**. Rozšířilo se to z téhož důvodu jako #73, #216 a #392: štítek, který
/// v repozitáři ještě není, se jinak musí založit v prohlížeči — tedy tím odskokem, kvůli kterému
/// #392 vzniklo. Co se **nezměnilo**: brána je tatáž, výčet je krátký a na jednom místě,
/// `GitHubGateway` zápis dál nemá.
///
/// **Merge přibyl u #465** — osmá metoda, a je to **vědomá změna zákazu**: do té doby stálo v tomhle
/// souboru i v `CLAUDE.md`, že merge sem nepatří, a `SingleWayOutTests` ho hlídaly jmenovitě.
/// Změnilo se to z téhož důvodu jako #73, #216, #392 a #413: mergnout vlastní PR, když je zeleno,
/// je poslední věc, kvůli které se od hotového review odskakuje do prohlížeče — a je to práce
/// s **vlastní** frontou, tedy tatáž třída jako labely a reviewery. Co se **nezměnilo**: brána je
/// tatáž (`PublishScope`), výčet je krátký a na jednom místě, `GitHubGateway` zápis dál nemá a v
/// zákazu zůstává approve mimo review, **zavření PR**, **milník** a **smazání labelu**.
///
/// Merge je přitom **nevratnější než všech sedm předchozích** — týká se `main`u, ne jen pull
/// requestu —, a platí se to dvěma věcmi navíc, které ostatní metody nemají: **potvrzením s úplným
/// výpisem** toho, co se stane (jako u review, #68), a **hlavou v payloadu** (`sha`), na kterou
/// GitHub odpoví `409`, když se větev mezitím pohnula.
///
/// **`deleteLabel` se nepřidá.** Není to opomenutí, je to hranice. Smazání labelu je jediná akce
/// v tomhle okně, po které nezůstane co opravit: label zmizí ze **všech** issues a PR, na kterých
/// leží, a z aplikace se ta ztráta nedá ani ukázat. Nevratnost se proto vyvažuje **potvrzením**, ne
/// opravnou akcí — a co se založí omylem, se maže tam, kde se i přebarvuje: na GitHubu.
///
/// **Každá metoda si sama ověří bránu `PublishScope`** — proto všechny berou adresu, ze které
/// se dá zjistit repo. Kdyby ji jedna z nich brát nemusela, existovala by cesta ven, která se
/// nedá zakázat v nastavení.
protocol ReviewPublishing: Sendable {
    /// Odešle rozdělané review. Vrací to, co GitHub potvrdil, ne to, co jsme poslali —
    /// z odpovědi je vidět, jak review doopravdy dopadlo.
    ///
    /// Před voláním si ověří, že repo je v `PublishScope`, že draft míří na aktuální hlavu
    /// PR a že je PR otevřený. **Při neshodě se nevolá nic.**
    func submit(_ draft: ReviewDraft) async throws -> SubmittedReview

    /// Odpoví do existujícího vlákna. Vrací komentář, jak ho potvrdil GitHub, takže se dá
    /// vložit do konverzace bez dalšího čtení.
    ///
    /// Pre-flight je **užší než u review**: ověřuje se scope a stav PR, ne `headSha`. Odpověď
    /// se váže na vlákno, ne na commit — odpovědět kolegovi na vlákno, které vzniklo před třemi
    /// pushi, je běžné, takže kontrola hlavy by zakazovala zrovna to, na co se odpovídá.
    /// Prázdné tělo se **neodesílá**: GitHub ho tiše spolkne (změřeno v sandboxu).
    func reply(to thread: ThreadTarget, body: String) async throws -> ThreadComment

    /// Označí vlákno za vyřešené, nebo ho otevře zpátky. Vrací stav i práva, jak je přepočítal
    /// GitHub.
    func setResolved(_ resolved: Bool, of thread: ThreadTarget) async throws -> ThreadResolution

    /// Napíše komentář do diskuze pod PR (#216). Vrací komentář, jak ho potvrdil GitHub, takže
    /// se dá vložit do konverzace bez dalšího čtení.
    ///
    /// Pre-flight je **stejně široký jako u odpovědi do vlákna**: scope a stav PR, ne `headSha`.
    /// Komentář pod PR se neváže na žádný commit — psát „mrknu na to zítra“ pod PR, který mezitím
    /// dostal push, je běžné, takže kontrola hlavy by zakazovala právě to.
    ///
    /// **Není to review.** Neposílá verdikt, nedá se jím schválit ani vyžádat změny a v panelu
    /// `Moje review` se neobjeví; to jde jedině `submit(_:)`, a to s potvrzením.
    func comment(on pullRequest: PRIdentifier, body: String) async throws -> ThreadComment

    /// Nastaví **celou** sadu labelů na PR (#392). Vrací ji, jak ji potvrdil GitHub, takže se dá
    /// zapsat do okna bez dalšího čtení.
    ///
    /// **Celá sada, ne přidání jednoho.** `PUT /issues/{n}/labels` sadu nahrazuje, takže rozdíl
    /// by se musel skládat podruhé tady — a dvě skládání téhož se rozejdou. Volající si sadu
    /// nechá spočítat od `Policy.toggledLabels`, která zároveň hlídá, že v ní není label, který
    /// repo nezná.
    ///
    /// Pre-flight je **stejně široký jako u komentáře**: scope a stav PR, ne `headSha`. Štítek se
    /// neváže na commit — přeštítkovat PR, který mezitím dostal push, je zrovna ta situace, kvůli
    /// které se štítkuje.
    func setLabels(_ labels: [String], on pullRequest: PRIdentifier) async throws -> [PullRequestLabel]

    /// Vyžádá review od uvedených lidí a týmů (#392). Vrací to, na koho se podle GitHubu čeká.
    ///
    /// **Jedna metoda na lidi i na týmy, ne dvě.** GitHub je bere jedním voláním
    /// (`reviewers` a `team_reviewers` v jednom payloadu), takže druhá metoda by výčet cest ven
    /// prodloužila za nic — a tvrdá podmínka č. 1 stojí na tom, že je ten výčet krátký.
    ///
    /// Slugy týmů se posílají **bez předpony organizace** — tak, jak je chce API a jak je dává
    /// `orgs/{org}/teams`.
    ///
    /// **Jen přidává.** Odebrat vyžádané review odsud nejde, a je to schválně: request pošle
    /// člověku upozornění, které se odebráním **nedá vzít zpět**, takže odebrání není opravný krok,
    /// jen zametení. Proto je u něj v okně jméno na tlačítku, ne `+` vedle avatara.
    ///
    /// Pre-flight jako u labelů — scope a stav PR, ne `headSha`.
    func requestReviewers(
        _ logins: [String],
        teams: [String],
        on pullRequest: PRIdentifier
    ) async throws -> RequestedReview

    /// Založí v repozitáři label, který v něm ještě není (#413). Vrací ho, jak ho potvrdil GitHub —
    /// z odpovědi je vidět jméno i barva, které doopravdy vznikly.
    ///
    /// **Bere pull request, i když zapisuje do repozitáře.** Není to nekonzistence, je to pojistka:
    /// zakládá se **kvůli** tomuhle PR a hned za tím jde `setLabels`, takže když PR otevřený není,
    /// druhé volání by neprošlo — a v repozitáři by po tom zbyl label, který nikdo nechtěl. Pre-flight
    /// je proto stejně široký jako u labelů (scope a stav PR, ne `headSha`) a **`pullRequest.repo` je
    /// zároveň ta adresa, ze které si metoda ověří bránu**.
    ///
    /// **Barva se posílá vždycky.** Vybírá ji `Policy.labelColor(for:)` z jména, takže je z čeho ji
    /// vzít při každém volání; kdyby byla volitelná, přiřadil by ji GitHub sám a náhled v potvrzení by
    /// ukazoval barvu, která nevznikla.
    ///
    /// **Prázdné jméno se neodesílá** (`PublishError.blankLabelName`), stejnou sdílenou kontrolou
    /// jako u odpovědi a komentáře. Label bez jména by GitHub odmítl 422, ale kontrola tady znamená,
    /// že se nevolá nic — a nabídka nabízí jedině neprázdné jméno, takže by se to jinak nezkoušelo.
    ///
    /// **Smazat label odsud nejde a nepůjde**, viz úvod souboru.
    func createLabel(
        _ label: PullRequestLabel,
        for pullRequest: PRIdentifier
    ) async throws -> PullRequestLabel

    /// Mergne pull request (#465). Vrací commit, který tím vznikl — tak, jak ho potvrdil GitHub.
    ///
    /// **Osmá metoda a ta nejnevratnější**: šest z předchozích sedmi sahalo na pull request nebo
    /// na diskuzi, sedmá na labely repozitáře — tohle mění `main`. Vyvažuje se to na dvou místech
    /// a obě jsou vidět: **potvrzení s úplným výpisem** toho, co se stane (`MergeSheet`, tatáž
    /// úvaha jako #68), a **hlava v payloadu**.
    ///
    /// Pre-flight je **širší než u labelů a užší než u review**. Ověřuje se scope, stav PR
    /// **a hlava** — hlava proto, že merge se na commit váže; mergnout kód, který jsi neviděl, je
    /// tatáž záměna jako approve na kód, který jsi neviděl. Na rozdíl od review je tady navíc
    /// **druhá pojistka v samotném volání**: `sha` v payloadu je pro GitHub podmínka, takže na
    /// commit pushnutý mezi pre-flightem a voláním odpoví `409` a nemergne nic. U review taková
    /// možnost není (změřeno u #62, že review se zastaralým `commit_id` projde).
    ///
    /// **Metodu si volající nevybírá.** Squash je jediná, kterou aplikace posílá, a je v jedné
    /// konstantě (`MergeRequest.method`) — proto ji plán nenese jako pole.
    func merge(_ plan: MergePlan) async throws -> MergedPullRequest
}
