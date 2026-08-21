import Foundation

/// Dvířka do AttributeGraphu: **co se právě přepočítává a kdo si o to řekl** (#361).
///
/// ## Proč vůbec
///
/// Po sedmi záchvatech je vylučovací seznam u #361 dlouhý a otázka pořád jedna: **co špiní atribut
/// umístění v líném seznamu**, takže `LazySubviewPlacements.updateValue()` nekonverguje. Ze
/// `sample`u se to dohledat nedá — v `Update.dispatchActions()` je vidět jen **re-arm**
/// (`signalPrefetch`), ne invalidace, protože ta vzniká uvnitř `flushTransactions`, ze kterého se
/// hlavní vlákno nevrátí. A ablace nad **usazenou** scénou už dvakrát „vyloučila“ něco, co v živém
/// kole je (`onGeometryChange` v `DiffPairBlockRowView`: #386 ji nad usazenou scénou vyloučila,
/// v sedmém záchvatu má 140 vzorků).
///
/// Zbývá tedy zeptat se toho, kdo to počítá — grafu samotného.
///
/// ## Co z toho jde (ověřeno spuštěním na macOS 26, ne z dokumentace)
///
/// `AGGraphDescription(nil, ["format": "stack/text", "max-frames": n])` vrátí **evaluační
/// zásobník** toho grafu, který se právě aktualizuje **na volajícím vlákně**. Vypadá takhle —
/// skutečný výstup z offscreen scény s `LazyVStack`em:
///
/// ```
///   #0: 90240 GeometryActionBinder<_GeometryActionModifier<CGRect>> -> ()
///   -- inputs:
///     89240[@120] DynamicBody<ViewBodyAccessor<ProbeRow>, …> -> …, changed
///   --
///   #9: 7600 LazySubviewPlacements<LazyVStackLayout> -> Array<_LazyLayout_PlacedSubview>
///   #10: 8032 LazyPreference<HostPreferencesKey> -> PreferenceValues
/// ```
///
/// Tedy přesně to, co u #361 chybí: **jména atributů** v celé řadě od toho, co se počítá teď
/// (`#0`), k tomu, kdo si o to řekl (poslední rámec), a u vstupů příznak `changed` — atribut,
/// jehož hodnota se doopravdy změnila. `LazySubviewPlacements` je v tom zásobníku vidět jmenovitě.
///
/// Změřené vlastnosti, na kterých ta instrumentace stojí:
///
/// - **Cena 0,0063 ms** na volání při `max-frames: 64` (500 volání v jednom průchodu tělem;
///   `max-frames: 8` dalo 0,0047 ms, takže rozhoduje volání, ne délka zásobníku).
/// - **Z cizího vlákna vrátí `nil`**, ne nesmysl a ne pád — vyzkoušeno z `Thread`u nad běžící
///   scénou. Vzorek se proto **musí** odebrat z hlavního vlákna zevnitř aktualizace; zapisovací
///   vlákno diagnostiky (#391) by se nedozvědělo nic.
/// - **Odkud je zásobník vidět**: z `View.body`, z `Layout.sizeThatFits`
///   i `placeSubviews`, z `of:` closure u `onGeometryChange` a z getteru identity, který si čte
///   `ForEach`. Z `action:` u `onGeometryChange` vrátí **nil** — akce běží mimo aktualizaci, což
///   je z druhé strany totéž zjištění jako „framework ji gatuje“ z #363.
/// - **Návratová hodnota je autoreleased, ne +1** — a je to zjištěné pádem, protože footprint
///   tvrdil opak. 100 000 volání bez `release` posunulo footprint procesu z 13,8 na 122,3 MB
///   (s `release` nerostl), z čehož to vypadalo na +1; jenže autorelease pool se v tom měření
///   nevyprázdnil ani jednou, takže rostla **jeho** fronta. `takeRetainedValue()` proto v testu
///   složil proces `SIGSEGV`em v `objc_release` uvnitř `AutoreleasePoolPage::releaseUntil` — tedy
///   over-release při vyprázdnění poolu. Bere se `takeUnretainedValue()` a celé volání je
///   ve **vlastním** `autoreleasepool`u: bez něj by se vzorky držely do konce kola runloopu, což je
///   u zaseknutého kola z #361 „nikdy“.
///
/// Co **nejde** (taky ověřeno spuštěním): `AGGraphGetCounter` chce `AGGraphRef`, a ten se zevnitř
/// `body` nedá vzít — `AGSubgraphGetCurrent()` je v té chvíli `nil` a `AGGraphGetAttributeGraph`
/// nad `AGGraphGetCurrentAttribute()` skončil `SIGABRT`em. Pojmenované counters
/// (`updates`, `changes`, `transactions`) vrací `AGGraphDescription(nil, ["format": "graph/dict",
/// "all_graphs": true])`, ale ten prochází **všechny uzly a hrany** (v jeho výstupu jsou vypsané),
/// takže to není nástroj na vzorek každou sekundu. Kolikrát se v tom kole umístění přepočítalo se
/// proto počítá **na naší straně** (`GraphSite`), ne z grafu.
///
/// ## Čím to nesmí být
///
/// - **Zapíná se jen s diagnostikou.** `dlopen` proběhne v `prepare()`, kterou volá
///   `RenderDiagnostics.start()`; bez `PRISM_DIAGNOSE=1` se privátní framework vůbec nenahraje
///   a `stack()` je jeden load `Optional`u.
/// - **Nic si neplánuje ani nemění.** Z celého AttributeGraphu se používá **jedna čtecí funkce**;
///   `AGGraphSetTrace` ani `AGGraphSetInvalidationCallback` ne, protože obojí si SwiftUICore
///   nastavuje samo (vidět v `dyld_info -imports`) a přepsat mu je znamená sáhnout do toho, co se
///   měří.
/// - **Chybějící symbol není pád.** Je to privátní API, takže příští systém ho může přejmenovat;
///   `prepare()` v takovém případě vrátí `false`, `stack()` `nil` a diagnostika to **napíše do
///   souboru** (`Policy.diagnosticGraphLine`) — „graf nic neřekl“ a „graf nejde otevřít“ se nemají
///   kde splést.
enum GraphProbe {
    /// Kolik rámců zásobníku se bere. Vyjmenovaná mez, ne odhad: rámce jsou generické názvy typů,
    /// takže je to zároveň strop na délku řádku v záznamu. Šestnáct stačí — v naměřeném zásobníku
    /// bylo dvanáct rámců od `body` až po `HostPreferencesTransform`.
    static let maxFrames = 16

    private typealias GraphDescription =
        @convention(c) (OpaquePointer?, CFDictionary) -> Unmanaged<CFTypeRef>?

    /// Nastavuje se **jednou** v `prepare()` a pak už se jen čte, stejně jako
    /// `RenderDiagnostics.current`.
    nonisolated(unsafe) private static var describe: GraphDescription?
    /// Postavené jednou, ne při každém volání: bridging slovníku do `CFDictionary` je alokace
    /// a tohle se volá zevnitř toho kola, které se měří.
    nonisolated(unsafe) private static var options: CFDictionary?

    /// Je zásobník k dispozici? Odpovídá na to, jestli se `dlopen` a `dlsym` povedly.
    static var isAvailable: Bool { describe != nil }

    /// Otevře AttributeGraph a najde tu jednu funkci. Vrací, jestli se to povedlo.
    ///
    /// Volá se z `RenderDiagnostics.start()`, tedy jedině se zapnutou diagnostikou. Druhé volání
    /// nic nedělá.
    @discardableResult static func prepare() -> Bool {
        guard describe == nil else { return true }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph", RTLD_LAZY
        ) else { return false }
        guard let symbol = dlsym(handle, "AGGraphDescription") else { return false }
        describe = unsafeBitCast(symbol, to: GraphDescription.self)
        options = ["format": "stack/text", "max-frames": maxFrames] as CFDictionary
        return true
    }

    /// Evaluační zásobník grafu, který se **na tomhle vlákně** právě aktualizuje.
    ///
    /// `nil` znamená jednu ze tří věcí a všechny jsou v pořádku: diagnostika je vypnutá, graf se
    /// tady neaktualizuje (jsme mimo `body`, mimo layout, na cizím vlákně), nebo systém tu funkci
    /// už nemá.
    static func stack() -> String? {
        guard let describe, let options else { return nil }
        // **Vlastní `autoreleasepool`, a to je celý rozdíl mezi nástrojem a únikem paměti**:
        // hodnota je autoreleased (viz dokumentace typu), takže by ji jinak držel pool kola
        // runloopu — a to kolo u #361 nedoběhne. `as? String` je bridging, který si drží svoje,
        // takže vrácený text pool nezasáhne.
        return autoreleasepool { () -> String? in
            guard let value = describe(nil, options) else { return nil }
            return value.takeUnretainedValue() as? String
        }
    }
}
