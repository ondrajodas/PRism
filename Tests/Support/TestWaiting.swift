import Foundation
import Testing

/// Čekání na jev v testech — jedno místo, kde je napsané, **jak** se čeká a **jak dlouho** (#296).
///
/// Vzniklo to tím, že tentýž problém našlo šest různých míst v repu zvlášť: `AsyncGate` (#292),
/// `ReviewSubmissionTests`, `HealthMonitorTests`, `AppStoreHealthTests`, `AppStoreNotificationTests`
/// a sonda odpočtu (#269). Každé si pak psalo vlastní odmlku s vlastním stropem, takže se oprava
/// dělala pokaždé znovu a v každém dalším testu se pattern začal od `Task.yield()`.
///
/// **Čeká se odmlkami, ne `Task.yield()`.** Yield práci nepustí na procesor — jen se přeřadí na
/// konec fronty téhož aktoru, takže se hot spin na `MainActoru` vrací pořád k sobě a hlavní smyčka
/// se k časovačům nedostane. Změřeno u #296: sonda odpočtu si v plném běhu vyžádala odmlku 100 ms
/// a probudila se za **7,5 až 8,6 s** — a vlastní práce sondy (bitmapa) přitom stála 1 ms. Nebyla
/// to tedy pomalá aplikace, ale vyhladovělý `MainActor`; suita, která na něm točí `yield()`, ubírá
/// čas všem ostatním, protože Swift Testing pouští suity paralelně.
///
/// **Strop je čas, ne počet kol.** Rozpočet kol (`for _ in 0..<100_000`) je pevný okamžik
/// v přestrojení: pod zátěží se vyčerpá dřív, než se čekaná práce vůbec dostane na procesor
/// (#292 — položilo to tři suity naráz). Rozpočet odmlek (`for _ in 0..<250` se spánkem) je proti
/// tomu odolný, ale z kódu se z něj nedá přečíst, jaký strop vlastně platí.
enum TestWait {
    /// Strop čekání na jev. **Je velkorysý schválně a je to strop proti zátěži, ne míra rychlosti** —
    /// kdo ho bude chtít snížit jako „přebujelý“, ať si napřed pustí plný běh testů při souběžném
    /// buildu tří slotů (#296).
    ///
    /// Z čeho je. Jevy, na které se tady čeká, jsou nad fake implementacemi a na volném stroji
    /// nastanou v jednotkách milisekund, takže strop neměří práci, ale **hladovění**. Změřeno na
    /// patnáctijádrovém stroji při třech souběžných clean buildech (load average 24–36, tedy
    /// přeobsazení asi 4×): jediná odmlka o 100 ms se probudila za **8,6 s** a čekání, která se
    /// nakonec **dočkala**, trvala až **24,6 s** — a to jsou ještě čísla ocenzurovaná stropem, který
    /// u toho měření byl 30 s a pod kterým padly tři běhy ze tří.
    ///
    /// Dvě minuty jsou proti tomu ~5× rezerva. Cena za velkorysost se platí **jen když je něco
    /// rozbité**: co se dočká, se dočká hned, takže strop nezdržuje zelený běh ani o milisekundu.
    /// A pořád platí to hlavní — rozbitý test **spadne**, nezasekne se, což je oproti neomezenému
    /// `while` cyklu, který tady byl do #296, celý rozdíl.
    static let deadline: Duration = .seconds(120)

    /// Jak často se sonda ptá. Milisekunda je dost na to, aby čekaná práce dostala vlákno,
    /// a málo na to, aby se test zdržel o víc, než na kolik se ptá.
    static let step: Duration = .milliseconds(1)

    /// Kolik času dostane rozdělaná práce v testu, který tvrdí, že se **nic nestalo** — viz
    /// `settle()`.
    ///
    /// Sto milisekund je kompromis, ne měřená hodnota, a je to slabé místo, které se nedá zesílit:
    /// „nic se nestalo“ nemá jev, na který by se čekalo, takže drain naslepo platí za to, kolik
    /// zbylo procesoru. Pod zátěží tedy ověřuje méně — ale **nemůže obarvit na červeno**, jen
    /// oslabit tvrzení. Kde jev existuje, patří tam `waitUntil`; přesně tak se u #296 opravil test
    /// draftu na disku, který na 50 ms drainu padal.
    static let settling: Duration = .milliseconds(100)

    /// Jedna odmlka pro smyčku, která **drží** práci rozběhnutou, dokud ji test nepustí.
    ///
    /// Držení stropovat nejde: běh se má zdržet přesně tak dlouho, jak si test řekne, a hlásit
    /// „nedočkalo se“ by tady znamenalo hlásit pád testu, který už dávno skončil. Co z čekání na
    /// jev platí i tady, je ta odmlka — spin na `yield()` bere procesor ostatním suitám.
    static func pause() async {
        try? await Task.sleep(for: step)
    }
}

/// Počká, dokud `condition` neplatí — v odmlkách, se stropem v čase.
///
/// Když se nedočká, **zapíše nález a vrátí `false`**, takže test spadne na místě čekání a v hlášce
/// stojí, co se nestalo. Do #296 se na těchto místech buď točil `yield()` bez stropu (test visel),
/// nebo se odtikal rozpočet kol a šlo se dál (test spadl o pár řádků níž na tvrzení, ze kterého
/// nebylo poznat, že se jen nedočkal).
///
/// `event` se dopisuje do věty „Nedočkalo se: …“, takže se píše jako **jev**, ne jako příkaz:
/// `„review doběhne“`, ne `„počkej na review“`.
@discardableResult
func waitUntil(
    _ event: String,
    within deadline: Duration = TestWait.deadline,
    step: Duration = TestWait.step,
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let limit = clock.now.advanced(by: deadline)
    while clock.now < limit {
        if await condition() { return true }
        // **Zrušení čekání ukončí**, a není to detail: `Task.sleep` na zrušeném tasku vyhodí
        // hned, takže bez téhle podmínky by se ze smyčky stal hot spin na celý strop — tedy
        // zrovna to pálení procesoru, kvůli kterému #296 vzniklo. Nastane to při `.timeLimit`
        // nebo když test zruší task, ve kterém se čeká.
        guard (try? await Task.sleep(for: step)) != nil else { return await condition() }
    }
    // Poslední kontrola za stropem: spánek umí na vytíženém stroji přetáhnout, takže by se jev,
    // který nastal těsně před koncem, jinak ohlásil jako nenastalý.
    if await condition() { return true }
    Issue.record("Nedočkalo se: \(event) (strop \(deadline)).", sourceLocation: sourceLocation)
    return false
}

/// Nechá rozdělanou práci doběhnout tam, kde **není podmínka, na kterou se dá čekat** — typicky
/// u testu, který tvrdí, že se nic nestalo, nebo u uložení, které si store rozjede vlastním
/// `Task`em a nikde to nehlásí.
///
/// Není na co čekat — čeká se, aby se ověřovaná věc měla kdy stát, kdyby se stát měla. Právě proto
/// je to jediné čekání v repu **bez podmínky a bez stropu**: strop by neměl co hlásit. Kde
/// podmínka existuje, patří tam `waitUntil` — ten se dočká hned a při chybě řekne, čeho se
/// nedočkal.
///
/// **Odmlka, ne `Task.yield()`ů dokola** (#296), a je silnější než rozpočet kol, který tu byl
/// předtím: yieldy dávají práci kola na tomtéž aktoru, kdežto odmlka dá čas i práci, která zatím
/// čeká na jiném vlákně — tedy zrovna tomu, co se u „nic se nestalo“ typicky testuje (spuštěný
/// `Task`, dotaz na fake gateway).
///
/// Cenu má jedině vedle testu, který tímtéž čekáním vidí, jak se ta věc **stát má** — sám o sobě
/// důkaz nenese, protože nedočkání se od nestání nedá odlišit.
func settle(
    _ duration: Duration = TestWait.settling,
    isolation: isolated (any Actor)? = #isolation
) async {
    try? await Task.sleep(for: duration)
}
