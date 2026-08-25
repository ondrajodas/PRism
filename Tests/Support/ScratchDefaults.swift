import Foundation

/// Vlastní doména `UserDefaults` pro **jeden test**, která po sobě uklidí — soubor
/// v `~/Library/Preferences` včetně (#411).
///
/// **Proč vlastní doména.** `UserDefaults.standard` je doména procesu, tedy něco, co test
/// nevlastní: hodnota v ní přežije běh, mění se podle toho, kdo běžel vedle, a v souběžném běhu
/// tří slotů do ní píše víc procesů naráz. Je to tatáž třída jako `NSApp.appearance` (#367) —
/// globální stav procesu.
///
/// **Proč jméno s `UUID`, a je to změřené, ne opatrnost.** Pojmenovaná doména je sdílená
/// **napříč procesy**, takže pevné jméno globálem být nepřestane, jen se to projeví teprve pod
/// souběžnou zátěží: u #420 si dvě sady s pevnými jmény (`cz.prism.tests.codeSheetSizing`,
/// `cz.prism.tests.rawSessionSheetSizing`) přepsaly klíč mezi slotmy a v testu, který tvrdil
/// `nil`, ležela cizí uložená šířka (1 180). Izolovaně obě sady procházely.
///
/// **Úklid má tři kroky a každý z nich je změřený**, protože „smazat doménu“ tady znamená něco
/// jiného, než jak to vypadá:
///
///  1. `removePersistentDomain(forName:)` **cizí instancí** (`UserDefaults()`), ne tou vrácenou:
///     instance, která si smaže vlastní doménu, si ji odebere i z prohledávaného seznamu a hodnoty
///     pak nedrží (poznatek z #327). Samo o sobě to ale **nestačí** — viz krok 2.
///  2. `defaults delete` **v podprocesu**. Zní to jako totéž, ale není: po samotném
///     `removePersistentDomain` se prázdný plist **vrátí, jakmile proces skončí** — v prvním plném
///     běhu po #411 takhle zůstalo **pět** souborů po 42 B, přesně těch, do kterých se zapisovalo.
///     Sonda to rozebrala na variantách: smazání zevnitř procesu se za živa jeví jako hotové
///     (soubor po `rm` není ani po dvou sekundách), ale při zániku procesu ho `cfprefsd` doflushuje
///     zpátky. Nevrátí se ve dvou případech — když se instance suity **pustí z ruky dřív**, než se
///     doména maže, a když domenu smaže **jiný proces**. Druhá cesta nezávisí na tom, kdo si na
///     instanci ještě drží odkaz (a v `deinit` se odkaz na vlastní pole pustit nedá), takže je
///     tady ta druhá.
///  3. `rm` toho souboru: `defaults delete` po sobě nechá **prázdný plist** (42 B), na kterém
///     `defaults read` už hlásí, že doména neexistuje — tatáž past jako u slotových domén v #399.
///     Že se `rm` povedl, se tvrdí **zpětným čtením**, ne návratovým kódem.
///
/// Zbývá jedna mezera a je vědomá: **zabitý běh** (⌃C nad `xcodebuild test`) úklid nespustí, takže
/// po něm může jeden soubor zůstat. Pozná se podle předpony a smaže rukou.
final class ScratchDefaults {
    /// Jméno domény. Předpona `cz.prism.tests.` je schválně jednotná: kdyby po spadlém běhu něco
    /// zbylo, je to podle ní na stroji poznat (`defaults domains | tr ',' '\n' | grep prism`).
    let name: String
    /// Doména jako `UserDefaults` — tohle se předává do `defaultAppStorage(_:)` nebo se z toho
    /// čte, co view uložilo.
    let store: UserDefaults
    /// Soubor, ve kterém doména leží. Drží se tady proto, že se maže **jmenovitě**, a proto, že
    /// se dá tvrdit, že po úklidu není.
    let plist: URL

    private var removed = false

    /// - Parameter label: k čemu ta doména v testu je; jde do jména, aby se případný zbytek na
    ///   stroji dal přiřadit k sadě, která ho tam nechala.
    init(_ label: String) throws {
        name = "cz.prism.tests.\(label).\(UUID().uuidString.lowercased())"
        plist = URL(filePath: NSHomeDirectory()).appending(path: "Library/Preferences/\(name).plist")
        guard let store = UserDefaults(suiteName: name) else {
            throw ScratchDefaultsError.suiteUnavailable(name)
        }
        self.store = store
    }

    /// Ukliď doménu i soubor po ní. Je to idempotentní, takže `deinit` po výslovném zavolání
    /// nedělá nic — a naopak test, který si `remove()` nezavolá, uklidí `deinit`.
    func remove() {
        guard !removed else { return }
        removed = true
        UserDefaults().removePersistentDomain(forName: name)
        deleteDomainFromAnotherProcess()
        try? FileManager.default.removeItem(at: plist)
        // Zbylý soubor se **hlásí**. Je to jediná věc, kterou tady umí prohrát nenápadně, a mlčení
        // by z ní udělalo přesně tu hromadu domén, kvůli které #411 vzniklo.
        if FileManager.default.fileExists(atPath: plist.path) {
            print("SCRATCH: po \(name) zůstal plist \(plist.path) — ukliď ho ručně.")
        }
    }

    /// Krok 2 z hlavičky. Návratový kód se **nečte**: `defaults delete` nad doménou, která
    /// neexistuje, vrací nenulu (změřeno u #399), takže o úspěchu nemluví — rozhoduje zpětné
    /// čtení souboru výš.
    private func deleteDomainFromAnotherProcess() {
        let delete = Process()
        delete.executableURL = URL(filePath: "/usr/bin/defaults")
        delete.arguments = ["delete", name]
        delete.standardOutput = FileHandle.nullDevice
        delete.standardError = FileHandle.nullDevice
        do {
            try delete.run()
        } catch {
            print("SCRATCH: `defaults delete \(name)` se nepodařilo spustit: \(error)")
            return
        }
        delete.waitUntilExit()
    }

    /// Úklid i pro test, který spadl. Tatáž volba jako u `TemporaryDirectory`: kdo si drží
    /// pomůcku, nemusí na úklid myslet.
    ///
    /// **Volající si přesto píše `defer { scratch.remove() }`**, a není to opakování téhož: kdo si
    /// z pomůcky vytáhne jen `store`, nemá ji dál v kódu použitou — a ARC ji smí pustit po
    /// **posledním použití**, ne na konci scope. Doména by pak zmizela uprostřed testu. `defer`
    /// to řeší z obou stran: je z něj vidět, kde úklid je, a drží pomůcku naživu do konce.
    deinit {
        remove()
    }
}

enum ScratchDefaultsError: Error {
    case suiteUnavailable(String)
}
