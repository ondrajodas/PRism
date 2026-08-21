import Foundation
import Testing

@testable import PRism

/// `bin/slot-cleanup.sh` — co po sobě slot nechává (#398, #399).
///
/// **Nejcennější tvrzení je tady to, že se něco NEstalo**: že se úklid nepustí na hlavní instanci.
/// Ta se pozná tím, že **nemá slotovou příponu**, takže z ní musí vyjít naprázdno — a nejde jen
/// o zdvořilost. V její cache leží uložené nálezy a rozdělané drafty, v její doméně proklikané
/// nastavení, a v `/Applications` je to ta aplikace, která se používá každý den.
///
/// Slot se v testech **vyrábí s UUID** a nikdy se nebere z `.prism-slot`: skript bez argumentu
/// slot ze stromu přečte, takže test bez argumentu by uklidil slot toho, kdo ho zrovna pustil.
/// Tři sloty přitom testují souběžně, takže vyrobené jméno je i ochrana proti tomu, aby si dva
/// běhy nesahaly na jednu doménu.
///
/// `PRISM_LSREGISTER` míří u většiny testů na `/usr/bin/true`: databáze LaunchServices se testuje
/// v `BundleLibraryTests`, tady je předmětem cache, doména a to, co skript odmítne. Dvě výjimky
/// jsou schválně obě chybové větve — kontrola, která hlásí jen výjimečně, se musí pustit i v tom
/// výjimečném stavu (#61).
@Suite("Úklid slotu")
struct SlotCleanupTests {
    private static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let script = repoRoot.appending(path: "bin/slot-cleanup.sh")

    private let home = URL(filePath: NSHomeDirectory())

    /// Slot, který na stroji nikdo nemá. Písmena, číslice a pomlčky — přesně to, co snese bundle ID.
    private func scratchSlot() -> String {
        "zztest-" + UUID().uuidString.lowercased()
    }

    private func cleanup(
        _ arguments: [String],
        lsregister: String = "/usr/bin/true"
    ) async throws -> ProcessResult {
        try await SubprocessRunner().run(
            Self.script,
            arguments: arguments,
            environment: ["PRISM_LSREGISTER": lsregister],
            timeout: .seconds(300)
        )
    }

    /// Existence a velikost toho, co patří hlavní instanci. Bere se před úklidem a po něm; když se
    /// změní, znamená to, že úklid slotu sáhl tam, kam nikdy sahat nesmí.
    private func mainInstanceFingerprint() -> [String] {
        let paths = [
            "/Applications/PRism.app",
            home.appending(path: "Library/Application Support/PRism").path,
            home.appending(path: "Library/Preferences/com.ondrajodas.prism.plist").path,
        ]
        return paths.map { path in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                return "\(path): není"
            }
            let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
            return "\(path): \(size)"
        }
    }

    // MARK: - Hlavní instance

    /// Prázdný slot je hlavní instance. Odmítnutí musí přijít **dřív, než se složí jakákoli cesta**,
    /// takže se kromě návratového kódu tvrdí i to, že se skript vůbec nerozjel — ani hlavičku
    /// „Uklízím slot“ nevypíše.
    @Test("Bez slotu se neuklízí nic")
    func refusesEmptySlot() async throws {
        let before = mainInstanceFingerprint()

        let result = try await cleanup([""])

        #expect(result.exitCode == 1)
        #expect(result.standardError.contains("hlavní instance"))
        #expect(!result.standardOutput.contains("Uklízím"))
        #expect(mainInstanceFingerprint() == before)
    }

    @Test("Slot se znakem mimo bundle ID se odmítne")
    func refusesSlotWithForbiddenCharacters() async throws {
        let result = try await cleanup(["a/../.."])

        #expect(result.exitCode == 1)
        #expect(result.standardError.contains("bundle ID"))
        #expect(!result.standardOutput.contains("Uklízím"))
    }

    @Test("Dva argumenty jsou chyba použití, ne úklid dvou slotů")
    func refusesTwoArguments() async throws {
        let result = try await cleanup(["a", "b"])

        #expect(result.exitCode == 1)
        #expect(result.standardError.contains("Použití"))
    }

    /// Slot, po kterém nic nezbylo, je normální stav — subagent, který si aplikaci nikdy
    /// nenainstaloval, uklízí prázdno. Nesmí z toho být chyba a hlavní instance se toho netkne.
    @Test("Slot, po kterém nic nezbylo, projde a hlavní instanci se nedotkne")
    func cleansSlotThatLeftNothing() async throws {
        let before = mainInstanceFingerprint()

        let result = try await cleanup([scratchSlot()])

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("bundle: v /Applications nebyl"))
        #expect(result.standardOutput.contains("cache: nebyla"))
        #expect(result.standardOutput.contains("doména v UserDefaults: nebyla"))
        #expect(mainInstanceFingerprint() == before)
    }

    // MARK: - Cache a doména

    @Test("Cache slotu se smaže")
    func deletesSlotCache() async throws {
        let slot = scratchSlot()
        let cache = home.appending(path: "Library/Application Support/PRism-\(slot)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try "{}".write(to: cache.appending(path: "config.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: cache) }

        let result = try await cleanup([slot])

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("smazáno: \(cache.path)"))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    /// #399 celé: doména **přežije smazání bundlu i cache**, takže by příští slot na tomtéž písmenu
    /// nastartoval s nastavením po předchůdci — tedy i s tím, co z něj `slot-config.sh` schválně
    /// vyndal. A `defaults delete` po sobě nechá **prázdný plist** (42 B), na kterém `defaults read`
    /// hlásí, že doména neexistuje; ověřit se to proto musí **zpětným čtením obojího**, ne
    /// návratovým kódem.
    @Test("Doména v UserDefaults i prázdný plist po ní zmizí")
    func deletesUserDefaultsDomainAndLeftoverPlist() async throws {
        let slot = scratchSlot()
        let domain = "com.ondrajodas.prism.\(slot)"
        let plist = home.appending(path: "Library/Preferences/\(domain).plist")
        try await defaultsWrite(domain: domain)
        defer { try? FileManager.default.removeItem(at: plist) }

        #expect(FileManager.default.fileExists(atPath: plist.path))

        let result = try await cleanup([slot])

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("smazána doména: \(domain)"))
        #expect(result.standardOutput.contains("smazán prázdný plist: \(plist.path)"))
        let stillReadable = try await defaultsReadSucceeds(domain: domain)
        #expect(stillReadable == false)
        #expect(!FileManager.default.fileExists(atPath: plist.path))
    }

    private static let defaults = URL(filePath: "/usr/bin/defaults")

    private func defaultsWrite(domain: String) async throws {
        let result = try await SubprocessRunner().run(
            Self.defaults,
            arguments: ["write", domain, "prismTestKey", "-bool", "true"],
            environment: [:],
            timeout: .seconds(60)
        )
        #expect(result.exitCode == 0)
    }

    private func defaultsReadSucceeds(domain: String) async throws -> Bool {
        let result = try await SubprocessRunner().run(
            Self.defaults,
            arguments: ["read", domain],
            environment: [:],
            timeout: .seconds(60)
        )
        return result.exitCode == 0
    }

    // MARK: - Chybové větve

    /// Chybějící `lsregister` je stav, který se **hlásí, ale nepokládá skript**: kvůli záznamu
    /// v databázi se nemá nespustit aplikace (#139) a zbytek úklidu se udělat má.
    @Test("Chybějící lsregister se ohlásí a zbytek úklidu proběhne")
    func reportsMissingLsregister() async throws {
        let result = try await cleanup([scratchSlot()], lsregister: "/nekde/takova/cesta/neni")

        #expect(result.exitCode == 3)
        #expect(result.standardError.contains("na čekané cestě není"))
        #expect(result.standardOutput.contains("cache: nebyla"))
        #expect(result.standardOutput.contains("zbývá to, co je vypsané výš"))
    }

    @Test("Neúspěšný lsregister se ohlásí a zbytek úklidu proběhne")
    func reportsFailingLsregister() async throws {
        let result = try await cleanup([scratchSlot()], lsregister: "/usr/bin/false")

        #expect(result.exitCode == 3)
        #expect(result.standardError.contains("výpis databáze LaunchServices neproběhl"))
        #expect(result.standardOutput.contains("doména v UserDefaults: nebyla"))
        #expect(result.standardOutput.contains("zbývá to, co je vypsané výš"))
    }

    // MARK: - Struktura skriptu

    /// Že úklid hlavní instance nejde **ani omylem**, se za běhu ověřit nedá: musela by se pustit
    /// ta cesta, která ji maže. Tvrdí se to proto nad zdrojákem — každý destruktivní příkaz sahá
    /// jedině na cestu složenou ze slotu, a slot je v tu chvíli neprázdný, protože `case` výš
    /// prázdný odmítl. Je to tatáž volba jako u `SingleWayOutTests`: „odkud se dá mazat“ je
    /// vlastnost struktury skriptu, na kterou se za běhu zeptat nedá.
    @Test("Každé mazání ve skriptu míří na cestu složenou ze slotu")
    func destructiveCommandsAreSlotScoped() throws {
        let text = try String(contentsOf: Self.script, encoding: .utf8)
        let lines = TextLines.content(text)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }

        // Jména, která se skládají ze slotu — a skládání samotné je taky tvrzení.
        #expect(lines.contains { $0.contains("NAME=\"PRism-${SLOT}\"") })
        #expect(lines.contains { $0.contains("BUNDLE_ID=\"com.ondrajodas.prism.${SLOT}\"") })
        #expect(lines.contains { $0.contains("INSTALLED=\"/Applications/${NAME}.app\"") })
        #expect(lines.contains { $0.contains("CACHE=") && $0.contains("${NAME}") })
        #expect(lines.contains { $0.contains("PLIST=") && $0.contains("${BUNDLE_ID}") })

        let slotScoped = ["${INSTALLED}", "${CACHE}", "${PLIST}", "${BUNDLE_ID}"]
        for line in lines where line.contains("rm -rf") || line.contains("rm -f") || line.contains("defaults delete") {
            #expect(slotScoped.contains { line.contains($0) }, "mazání mimo slot: \(line)")
        }

        // `killall` by sestřelil i instanci, se kterou pracuje někdo jiný — a rozdělané review
        // s ní. Ukončuje se Apple eventem na bundle ID, stejně jako v `run.sh`.
        #expect(!lines.contains { $0.contains("killall") })
    }
}
