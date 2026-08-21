import Foundation
import Testing

@testable import PRism

/// `bin/lib/bundles.sh` — knihovna nad PRism bundly a nad databází LaunchServices (#398).
///
/// **Spouští se, ne čte.** Obojí, co je v knihovně, rozhoduje o mazání: jedna funkce říká, jestli
/// je bundle na cestě náš (a tedy jestli se smí přepsat nebo smazat), druhá odregistrovává záznamy
/// z databáze. Přečtený `case` v takovém skriptu nedokazuje nic — u #61 tu ležela kontrola podpisu,
/// která nevypsala nic ani v tom stavu, na který se ptala, protože `| grep -q` s `pipefail` vrací
/// 141. Proto se tady volají skutečné funkce skutečným bashem.
///
/// **Sonda si vyrábí vlastní bundly** v `TemporaryDirectory` a registruje je do **skutečné**
/// databáze LaunchServices — jinak by nebylo co odregistrovávat. Jmenují se `PRism-…`, aby je filtr
/// knihovny našel, a leží mimo `/Applications`, takže se z nich nemůže stát aplikace, ze které se
/// v Launchpadu nedá vybrat. Vedlejší účinek běhu je, že se zametou i **skutečné** zaniklé záznamy
/// (u #398 jich na stroji leželo čtrnáct) — je to přesně to, co má knihovna dělat, jen se to
/// nekoná v ohrádce.
@Suite("Knihovna nad PRism bundly")
struct BundleLibraryTests {
    private static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let library = repoRoot.appending(path: "bin/lib/bundles.sh")

    private let workspace: TemporaryDirectory
    /// **Rozřešená** cesta k pracovní složce. `NSTemporaryDirectory()` vrací `/var/folders/…`,
    /// kdežto LaunchServices si pamatuje `/private/var/folders/…` — `/var` je symlink. Bez tohohle
    /// by tvrzení o vypsané cestě neplatilo, i když by úklid proběhl správně (u #398 kvůli tomu
    /// test spadl a databáze byla přitom uklizená).
    ///
    /// A `resolvingSymlinksInPath()` na to **není** — jde záměrně druhou stranou a `/private`
    /// naopak odřezává (změřeno: `/var/folders/…` zůstalo `/var/folders/…`). Rozřešení proto dělá
    /// `realpath(3)`, který cestu vrací tak, jak ji vidí jádro.
    private let root: URL

    init() throws {
        workspace = try TemporaryDirectory()
        root = Self.realPath(of: workspace.url)
    }

    private static func realPath(of url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved))
    }

    /// Zavolá funkci z knihovny. `$0` je cesta ke knihovně, `$1` a dál jsou argumenty testu —
    /// tak jak je `bash -c` rozdává.
    private func call(
        _ snippet: String,
        _ arguments: String...,
        environment: [String: String] = [:]
    ) async throws -> ProcessResult {
        try await SubprocessRunner().run(
            URL(filePath: "/bin/bash"),
            arguments: ["-c", "set -euo pipefail; . \"$0\"; \(snippet)", Self.library.path] + arguments,
            environment: environment,
            timeout: .seconds(300)
        )
    }

    /// Nejmenší bundle, který LaunchServices vezme: `Info.plist` s identifikátorem a spustitelný
    /// soubor, na který ukazuje `CFBundleExecutable`.
    private func makeBundle(named name: String, identifier: String) throws -> URL {
        let bundle = root.appending(path: "\(name).app")
        let binary = bundle.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: binary, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleExecutable": "PRism",
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: bundle.appending(path: "Contents/Info.plist"))
        let executable = binary.appending(path: "PRism")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return bundle
    }

    // MARK: - Kdo je náš

    @Test("Náš bundle projde, cizí identifikátor ne")
    func tellsOurBundleFromForeign() async throws {
        let bundle = try makeBundle(named: "PRism-ours", identifier: "com.ondrajodas.prism.ours")

        let ours = try await call("prism_bundle_is_ours \"$1\" \"$2\"", bundle.path, "com.ondrajodas.prism.ours")
        #expect(ours.exitCode == 0)

        let foreign = try await call("prism_bundle_is_ours \"$1\" \"$2\"", bundle.path, "com.example.cizi")
        #expect(foreign.exitCode != 0)
        // Hlásí, **co** tam našel — bez toho je odmítnutí nevysvětlitelné.
        #expect(foreign.standardError.contains("com.ondrajodas.prism.ours"))
    }

    /// Bundle bez `Info.plist` je taky „nevím, čí to je“, a to znamená nemazat.
    ///
    /// Druhá polovina tvrzení je o **hlášce**, a je to nález z prvního běhu tohohle testu:
    /// `PlistBuddy` píše chyby na **stdout**, takže se z `File Doesn't Exist, Will Create: …` stal
    /// „identifikátor“ a hlášení o cizím bundlu z toho bylo nesmyslné. Odmítnutí dopadlo správně,
    /// jen se nedalo přečíst — přesně ten druh vady, který zelený test nechytí, dokud se text
    /// netvrdí.
    @Test("Bundle bez Info.plist se nepovažuje za náš")
    func refusesBundleWithoutIdentifier() async throws {
        let bundle = root.appending(path: "PRism-bezplistu.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let result = try await call("prism_bundle_is_ours \"$1\" \"$2\"", bundle.path, "com.ondrajodas.prism.a")

        #expect(result.exitCode != 0)
        #expect(result.standardError.contains("neznámý"))
        #expect(!result.standardError.contains("Will Create"))
    }

    /// Tentýž případ o krok dál: `Info.plist` je, ale klíč v něm ne. Tady `PlistBuddy` píše chybu
    /// na **stderr** — což je zrovna ten rozdíl, kvůli kterému se hlášky nefiltrují podle textu,
    /// ale rozhoduje návratový kód.
    @Test("Info.plist bez identifikátoru se nepovažuje za náš")
    func refusesBundleWithoutIdentifierKey() async throws {
        let bundle = root.appending(path: "PRism-bezklice.app")
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleName": "PRism-bezklice"],
            format: .xml,
            options: 0
        )
        try data.write(to: bundle.appending(path: "Contents/Info.plist"))

        let result = try await call("prism_bundle_is_ours \"$1\" \"$2\"", bundle.path, "com.ondrajodas.prism.a")

        #expect(result.exitCode != 0)
        #expect(result.standardError.contains("neznámý"))
        #expect(!result.standardError.contains("Does Not Exist"))
    }

    /// Třetí případ, který ten první průchod #398 **neuměl** a našlo se to až měřením: `Info.plist`
    /// existuje, ale nedá se přečíst. `PlistBuddy` na to vypíše na stdout `Error Reading File: …`,
    /// takže filtr podle textu tady mlčel a hláška se stala identifikátorem.
    @Test("Rozbitý Info.plist se nepovažuje za náš")
    func refusesBundleWithUnreadableIdentifier() async throws {
        let bundle = root.appending(path: "PRism-rozbity.app")
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"),
            withIntermediateDirectories: true
        )
        try "tohle není plist\n".write(
            to: bundle.appending(path: "Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await call("prism_bundle_is_ours \"$1\" \"$2\"", bundle.path, "com.ondrajodas.prism.a")

        #expect(result.exitCode != 0)
        #expect(result.standardError.contains("neznámý"))
        #expect(!result.standardError.contains("Error Reading File"))
    }

    /// Na neexistující cestě není co chránit, takže se odpovídá „projde“ — volající tam bude psát
    /// (`run.sh` instaluje) nebo nebude mazat nic (`slot-cleanup.sh`). Kdyby se odpovídalo obráceně,
    /// `run.sh` by odmítl nainstalovat aplikaci do čisté složky.
    @Test("Neexistující cesta není cizí bundle")
    func acceptsMissingPath() async throws {
        let missing = root.appending(path: "PRism-neni.app")

        let result = try await call("prism_bundle_is_ours \"$1\" \"$2\"", missing.path, "com.ondrajodas.prism.a")

        #expect(result.exitCode == 0)
        #expect(result.standardError.isEmpty)
    }

    // MARK: - Cesta k lsregister

    @Test("Cesta k lsregister je absolutní a dá se přebít")
    func resolvesLsregister() async throws {
        let standard = try await call("prism_lsregister_path")
        #expect(standard.standardOutput.contains("LaunchServices.framework"))
        #expect(standard.standardOutput.hasPrefix("/"))

        let overridden = try await call(
            "prism_lsregister_path",
            environment: ["PRISM_LSREGISTER": "/usr/bin/true"]
        )
        #expect(overridden.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "/usr/bin/true")
    }

    /// Chybějící binárka se **hlásí** a vrací nenulu; volající kvůli tomu nemá skončit, protože
    /// kvůli záznamu v databázi se nemá nespustit aplikace (#139).
    @Test("Chybějící lsregister se ohlásí, ne spolkne")
    func reportsMissingLsregister() async throws {
        let unregister = try await call(
            "prism_unregister /tmp/PRism-neni.app",
            environment: ["PRISM_LSREGISTER": "/nekde/takova/cesta/neni"]
        )
        #expect(unregister.exitCode != 0)
        #expect(unregister.standardError.contains("na čekané cestě není"))

        let prune = try await call(
            "prism_sweep_registrations",
            environment: ["PRISM_LSREGISTER": "/nekde/takova/cesta/neni"]
        )
        #expect(prune.exitCode != 0)
        #expect(prune.standardError.contains("zaniklé záznamy"))
    }

    /// Druhá chybová větev: binárka je, ale výpis databáze neproběhne. Nesmí to splynout s „nic
    /// zaniklého tam není“ — proto se návratový kód `lsregister` čte, a ne posílá do roury.
    @Test("Neúspěšný výpis databáze se nevydává za čisto")
    func reportsFailingDump() async throws {
        let result = try await call(
            "prism_sweep_registrations",
            environment: ["PRISM_LSREGISTER": "/usr/bin/false"]
        )

        #expect(result.exitCode != 0)
        #expect(result.standardError.contains("výpis databáze LaunchServices neproběhl"))
        #expect(!result.standardOutput.contains("zaniklý záznam o PRism bundlu v ní není"))
    }

    // MARK: - Zametení zaniklých záznamů

    /// Jádro #398 na třech bundlech naráz, protože každý zastupuje jeden skutečný případ:
    ///
    /// - `stale` je zaniklé worktree nebo smazaný slotový bundle — registrace po něm zůstala,
    ///   protože **smazání bundlu záznam nesundá** (#139);
    /// - `keep` je hlavní `/Applications/PRism.app` a aplikace jiného slotu, na které pracuje někdo
    ///   jiný. **Toto je ta cennější polovina tvrzení**: nevybírá se podle jména, ale podle toho, co
    ///   na disku chybí — a hlavní aplikace tam je, takže z úklidu musí vyjít nedotčená;
    /// - `built` je výsledek buildu v `build.noindex/`, který na disku **zůstává**, ale spouští se
    ///   kopie z `/Applications`. Předává se jmenovitě v argumentu, jinak by ho výběr přeskočil.
    ///
    /// Jeden běh, dva výpisy databáze (~2,4 s každý), takže se checkpointy dělají po jednom výpisu
    /// a hledá se v souboru — ne runda `lsregister -dump` na každou cestu.
    @Test("Zaniklý záznam a vyjmenovaná cesta jdou pryč, existující bundle zůstane")
    func sweepsVanishedAndRequestedPaths() async throws {
        let stale = try makeBundle(named: "PRism-stale", identifier: "com.ondrajodas.prism.stale")
        let keep = try makeBundle(named: "PRism-keep", identifier: "com.ondrajodas.prism.keep")
        let built = try makeBundle(named: "PRism-built", identifier: "com.ondrajodas.prism.built")
        defer { try? unregisterForTeardown(keep) }
        defer { try? unregisterForTeardown(built) }

        try await register(stale)
        try await register(keep)
        try await register(built)

        let afterRegistration = try await dumpDatabase()
        let staleWasRegistered = try await isRegistered(stale, in: afterRegistration)
        let keepWasRegistered = try await isRegistered(keep, in: afterRegistration)
        let builtWasRegistered = try await isRegistered(built, in: afterRegistration)
        #expect(staleWasRegistered)
        #expect(keepWasRegistered)
        #expect(builtWasRegistered)

        try FileManager.default.removeItem(at: stale)

        let sweep = try await call("prism_sweep_registrations \"$1\"", built.path)
        #expect(sweep.exitCode == 0)
        #expect(sweep.standardOutput.contains("odregistrováno: \(stale.path)"))
        #expect(sweep.standardOutput.contains("odregistrováno: \(built.path)"))
        #expect(!sweep.standardOutput.contains("odregistrováno: \(keep.path)"))

        let afterSweep = try await dumpDatabase()
        let staleSurvived = try await isRegistered(stale, in: afterSweep)
        let builtSurvived = try await isRegistered(built, in: afterSweep)
        let keepSurvived = try await isRegistered(keep, in: afterSweep)
        #expect(staleSurvived == false)
        #expect(builtSurvived == false)
        #expect(keepSurvived)
        // Bundle se nemaže, jen záznam o něm — to je celý rozsah téhle funkce.
        #expect(FileManager.default.fileExists(atPath: built.path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
    }

    /// Nález ze skutečného běhu: `lsregister -u` vrací **nenulu i nad cestou, která v databázi
    /// vůbec není** (`failed to scan … -10814`), takže první verze #398 hlásila „nepodařilo se
    /// odregistrovat“ nad kopií, kterou `run.sh` odregistroval o minutu dřív — poplach nad hotovou
    /// prací a `exit 3` z úklidu, který dopadl dobře. Proto se `-u` volá jedině na to, co v prvním
    /// výpisu doopravdy je, a tvrdí se to i tady: vyjmenovaná, ale neregistrovaná cesta nic nehlásí.
    @Test("Vyjmenovaná cesta, která v databázi není, nevyrábí poplach")
    func staysQuietAboutUnregisteredPath() async throws {
        let never = root.appending(path: "PRism-nikdy-neregistrovany.app")
        try FileManager.default.createDirectory(at: never, withIntermediateDirectories: true)

        let sweep = try await call("prism_sweep_registrations \"$1\"", never.path)

        #expect(sweep.exitCode == 0)
        #expect(!sweep.standardError.contains("Pozor"))
        #expect(!sweep.standardOutput.contains("odregistrováno: \(never.path)"))
    }

    private static let lsregister = URL(
        filePath: "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks"
            + "/LaunchServices.framework/Versions/A/Support/lsregister"
    )

    private func register(_ bundle: URL) async throws {
        let result = try await SubprocessRunner().run(
            Self.lsregister,
            arguments: ["-f", bundle.path],
            environment: [:],
            timeout: .seconds(120)
        )
        #expect(result.exitCode == 0)
    }

    private func unregisterForTeardown(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = Self.lsregister
        process.arguments = ["-u", bundle.path]
        try process.run()
        process.waitUntilExit()
    }

    private func dumpDatabase() async throws -> URL {
        let dump = root.appending(path: "dump-\(UUID().uuidString).txt")
        let result = try await SubprocessRunner().run(
            URL(filePath: "/bin/bash"),
            arguments: ["-c", "\"$0\" -dump > \"$1\" 2>/dev/null", Self.lsregister.path, dump.path],
            environment: [:],
            timeout: .seconds(300)
        )
        #expect(result.exitCode == 0)
        return dump
    }

    /// Hledá se `grepem` nad souborem, ne načtením 23 MB do řetězce. `grep -c` navíc dočte celý
    /// vstup, takže tady nehrozí ten SIGPIPE, kterým `| grep -q` obrací podmínku naruby.
    private func isRegistered(_ bundle: URL, in dump: URL) async throws -> Bool {
        let result = try await SubprocessRunner().run(
            URL(filePath: "/usr/bin/grep"),
            arguments: ["-c", "-F", bundle.path, dump.path],
            environment: [:],
            timeout: .seconds(120)
        )
        let count = Int(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return count > 0
    }

    // MARK: - Jedno místo, dva volající

    /// #398 chtělo **jedno** místo, které se volá z `run.sh` i z úklidu slotu. Kdyby si kterýkoli
    /// z nich odregistrování nebo kontrolu identity opsal k sobě, byla by to zpátky ta situace
    /// z #262: dvě kopie a příští oprava jen v jedné.
    @Test("Odregistrování a kontrola identity nemají druhou kopii")
    func keepsOneImplementation() throws {
        let scripts = ["bin/run.sh", "bin/slot-cleanup.sh"]
        for script in scripts {
            let text = try String(contentsOf: Self.repoRoot.appending(path: script), encoding: .utf8)
            let code = TextLines.content(text)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
                .joined(separator: "\n")

            #expect(code.contains(". bin/lib/bundles.sh"), "\(script) knihovnu nesourcuje")
            #expect(code.contains("prism_sweep_registrations"), "\(script) nezametá databázi")
            // Vlastní cesta k `lsregister` ani vlastní čtení identifikátoru — obojí je v knihovně.
            #expect(!code.contains("LaunchServices.framework"), "\(script) si opsal cestu k lsregister")
            #expect(!code.contains("PlistBuddy"), "\(script) si opsal čtení identifikátoru bundlu")
        }
    }
}
