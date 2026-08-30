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
///
/// **Hlavní instance se v téhle sadě vyrábí, ne čte** (#411, mění #398). Do #411 se tvrzení „úklid
/// slotu tam nesáhl“ opíralo o otisk **skutečné** hlavní instance, tedy i o velikost
/// `~/Library/Preferences/com.ondrajodas.prism.plist` — a do toho souboru píše **běžící aplikace**,
/// která je na tomhle stroji spuštěná celý den. Naměřeno na plných bězích: 6 296 → 6 343,
/// 6 563 → 6 566, 7 263 → 7 266 B, a velikost se pak **vrací**, takže se během běhu jen přepíše.
/// Izolovaně sada procházela 9/9 za 0,1 s, v plném běhu (40–67 s) byla **dvakrát falešně červená**.
/// Rozhodovala délka běhu, ne obsah změny.
///
/// Otisk se proto bere z **podstrčeného `HOME`** (`MainInstanceDecoy`), kde cache i plist hlavní
/// instance vyrobí test — má tedy pod kontrolou obojí konec tvrzení a čte jen svoje soubory.
/// Ověřuje se u toho **obsah, ne velikost**, což je silnější než původní podoba.
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
        lsregister: String = "/usr/bin/true",
        home: URL? = nil
    ) async throws -> ProcessResult {
        var environment = ["PRISM_LSREGISTER": lsregister]
        if let home {
            environment["HOME"] = home.path
        }
        return try await SubprocessRunner().run(
            Self.script,
            arguments: arguments,
            environment: environment,
            timeout: .seconds(300)
        )
    }

    /// Vyrobená hlavní instance v podstrčeném `HOME`: cache a plist **na těch jménech, která hlavní
    /// instance doopravdy má**. Skript si obojí skládá z `${HOME}`, takže se mu dá dát jiný domov
    /// a tvrzení „nesáhl na hlavní instanci“ vést nad soubory, do kterých nikdo jiný nepíše.
    ///
    /// **Doména v `UserDefaults` se takhle podstrčit nedá, a je to změřené** — `defaults` `HOME`
    /// ignoruje (zápis pod podstrčeným domovem skončil v tom skutečném, protože cestu skládá
    /// `cfprefsd`, ne klient). Nevadí: doména se testuje zvlášť na slotu s `UUID`
    /// (`deletesUserDefaultsDomainAndLeftoverPlist`) a hlavní instance se tady poznává po cestách.
    ///
    /// **Že skript ten podstrčený domov doopravdy používá, tvrdí `deletesSlotCache`** — bez toho
    /// pozitivního kontrolního testu by byla všechna tvrzení níž prázdná, protože nedotčené soubory
    /// by znamenaly i „skript se na ně nikdy nepodíval“.
    private struct MainInstanceDecoy {
        /// Drží se, aby se složka smazala až s testem.
        let root: TemporaryDirectory
        let cache: URL
        let plist: URL

        static let cacheContent = "{\"nálezy\":\"nesmí se smazat\"}"
        static let plistContent = "<plist>proklikané nastavení</plist>"

        init() throws {
            root = try TemporaryDirectory()
            cache = root.url.appending(path: "Library/Application Support/PRism")
            plist = root.url.appending(path: "Library/Preferences/com.ondrajodas.prism.plist")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: plist.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.cacheContent.write(to: cache.appending(path: "findings.json"), atomically: true, encoding: .utf8)
            try Self.plistContent.write(to: plist, atomically: true, encoding: .utf8)
        }

        /// Obsah obojího, jak ho po sobě našel test. Porovnává se **obsah**, ne velikost: soubor
        /// přepsaný na stejnou délku by jinak prošel.
        func fingerprint() -> [String] {
            [cache.appending(path: "findings.json"), plist].map { url in
                (try? String(contentsOf: url, encoding: .utf8)) ?? "není"
            }
        }

        var untouched: Bool {
            fingerprint() == [Self.cacheContent, Self.plistContent]
        }
    }

    // MARK: - Hlavní instance

    /// Prázdný slot je hlavní instance. Odmítnutí musí přijít **dřív, než se složí jakákoli cesta**,
    /// takže se kromě návratového kódu tvrdí i to, že se skript vůbec nerozjel — ani hlavičku
    /// „Uklízím slot“ nevypíše.
    @Test("Bez slotu se neuklízí nic")
    func refusesEmptySlot() async throws {
        let decoy = try MainInstanceDecoy()

        let result = try await cleanup([""], home: decoy.root.url)

        #expect(result.exitCode == 1)
        #expect(result.standardError.contains("hlavní instance"))
        #expect(!result.standardOutput.contains("Uklízím"))
        #expect(decoy.untouched, "Hlavní instance se změnila: \(decoy.fingerprint())")
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
        let decoy = try MainInstanceDecoy()

        let result = try await cleanup([scratchSlot()], home: decoy.root.url)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("bundle: v /Applications nebyl"))
        #expect(result.standardOutput.contains("cache: nebyla"))
        #expect(result.standardOutput.contains("doména v UserDefaults: nebyla"))
        #expect(decoy.untouched, "Hlavní instance se změnila: \(decoy.fingerprint())")
    }

    // MARK: - Cache a doména

    /// **Zároveň pozitivní kontrola k podstrčenému `HOME`**: cache leží vedle vyrobené hlavní
    /// instance a smazat se má jen ta slotová. Bez tohohle testu by tvrzení „hlavní instance je
    /// nedotčená“ mohla projít i tehdy, kdyby skript o podstrčeném domovu vůbec nevěděl.
    @Test("Cache slotu se smaže")
    func deletesSlotCache() async throws {
        let decoy = try MainInstanceDecoy()
        let slot = scratchSlot()
        let cache = decoy.root.url.appending(path: "Library/Application Support/PRism-\(slot)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try "{}".write(to: cache.appending(path: "config.json"), atomically: true, encoding: .utf8)

        let result = try await cleanup([slot], home: decoy.root.url)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("smazáno: \(cache.path)"))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(decoy.untouched, "Hlavní instance se změnila: \(decoy.fingerprint())")
    }

    /// #399 celé: doména **přežije smazání bundlu i cache**, takže by příští slot na tomtéž písmenu
    /// nastartoval s nastavením po předchůdci — tedy i s tím, co z něj `slot-config.sh` schválně
    /// vyndal. A `defaults delete` po sobě nechá **prázdný plist** (42 B), na kterém `defaults read`
    /// hlásí, že doména neexistuje; ověřit se to proto musí **zpětným čtením obojího**, ne
    /// návratovým kódem.
    ///
    /// **Tenhle jediný test běží ve skutečném `HOME`** (#411): `defaults` `HOME` ignoruje —
    /// změřeno, zápis pod podstrčeným domovem skončil v tom skutečném, protože cestu skládá
    /// `cfprefsd`, ne klient. Skript by tedy hledal plist jinde, než kam ho `defaults` položil,
    /// a test by tvrdil něco o prázdnu. Bezpečné to je proto, že slot má `UUID`: doména i soubor
    /// jsou naše a nikdo jiný je nemá.
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

    // MARK: - Záznamy v ~/.claude.json

    /// Konfigurace Claude Code v podstrčeném `HOME`, ve které leží vedle sebe **záznamy slotu
    /// a záznamy, kterých se úklid nesmí dotknout** (#484).
    ///
    /// Klíče se skládají `ClaudeWorkspaceTrust.key(for:)`, tedy **toutéž funkcí, kterou je do
    /// souboru zapisuje aplikace** — je to rozvinutá cesta (`realpath`), a `${TMPDIR}` testovacího
    /// hosta leží za symlinkem (`/var` → `/private/var`). Klíč složený od oka by se s tím, co
    /// v souboru doopravdy stojí, minul.
    ///
    /// Kořen slotu je tu schválně **dvakrát**: jednou jak ho vidí skript ze svého `${HOME}`
    /// a jednou rozvinutý. Obě podoby musí zmizet, protože která z nich v souboru stojí, závisí
    /// na tom, jestli domovská složka leží za symlinkem.
    private struct ClaudeConfigDecoy {
        let file: URL
        /// Klíče, které se mají smazat, a klíče, které musí zůstat.
        let doomed: [String]
        let spared: [String]

        static func make(home: URL, slot: String) throws -> ClaudeConfigDecoy {
            let support = home.appending(path: "Library/Application Support")
            let cache = support.appending(path: "PRism-\(slot)")
            let worktree = cache.appending(path: "worktrees/cli-gh-1")
            // Slot, jehož jméno začíná tím naším — bez lomítka v porovnání by ho úklid vzal s sebou.
            let sibling = support.appending(path: "PRism-\(slot)b/repos/cli-gh.git")
            let main = support.appending(path: "PRism/repos/cli-gh.git")
            for directory in [worktree, sibling, main] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let doomed = [
                cache.path(percentEncoded: false),
                ClaudeWorkspaceTrust.key(for: cache),
                ClaudeWorkspaceTrust.key(for: worktree),
            ]
            let spared = [
                ClaudeWorkspaceTrust.key(for: sibling),
                ClaudeWorkspaceTrust.key(for: main),
                "/Users/nekdo/Projects/cizi-projekt",
            ]
            var projects: [String: Any] = [:]
            for key in doomed + spared {
                projects[key] = ["hasTrustDialogAccepted": true]
            }
            let root: [String: Any] = ["numStartups": 7, "projects": projects]
            let file = home.appending(path: ".claude.json")
            try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]).write(to: file)
            return ClaudeConfigDecoy(file: file, doomed: doomed, spared: spared)
        }

        func projectKeys() throws -> Set<String> {
            let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            let root = decoded as? [String: Any]
            return Set((root?["projects"] as? [String: Any])?.keys.map { $0 } ?? [])
        }

        /// Co v souboru zůstalo mimo `projects` — přepis nesmí zahodit zbytek konfigurace.
        func startups() throws -> Int? {
            let decoded = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            return (decoded as? [String: Any])?["numStartups"] as? Int
        }
    }

    /// Aplikace zapisuje do `~/.claude.json` důvěru ke složkám **své** cache (#460), od #479 ke
    /// každému pracovnímu stromu review zvlášť — takže záznamů po slotu zbývají desítky a bundle,
    /// cache ani doména je s sebou nevezmou (#484).
    ///
    /// **Nejcennější půlka tohohle testu je ta negativní**: sousední slot, jehož jméno začíná tím
    /// naším, hlavní instance a cizí projekt musí zůstat. Ubraný cizí klíč by byl potichu — nikdo
    /// se na ten soubor nedívá, dokud se `claude` nezeptá na důvěru ke složce, kterou už znal.
    @Test("Záznamy slotu v ~/.claude.json zmizí, cizí ani hlavní instance ne")
    func deletesSlotProjectsFromClaudeConfig() async throws {
        let decoy = try MainInstanceDecoy()
        let slot = scratchSlot()
        let config = try ClaudeConfigDecoy.make(home: decoy.root.url, slot: slot)

        let result = try await cleanup([slot], home: decoy.root.url)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("smazáno záznamů v \(config.file.path)"))
        let remaining = try config.projectKeys()
        for key in config.doomed {
            #expect(!remaining.contains(key), "záznam slotu zůstal: \(key)")
        }
        for key in config.spared {
            #expect(remaining.contains(key), "smazal se cizí záznam: \(key)")
        }
        #expect(try config.startups() == 7, "přepis zahodil zbytek konfigurace")
        #expect(decoy.untouched, "Hlavní instance se změnila: \(decoy.fingerprint())")
    }

    /// Soubor, ve kterém po slotu nic není, se **nepřepisuje vůbec** — porovnávají se bajty, takže
    /// by test spadl i na pouhém přeskládání klíčů. Přepsat cizí konfiguraci bez důvodu je zbytečné
    /// riziko: `claude` do ní zapisuje sám a každý zápis je okno, ve kterém se dá o cizí změnu přijít.
    @Test("Konfigurace bez záznamů slotu zůstane bajt po bajtu stejná")
    func leavesClaudeConfigWithoutSlotKeysAlone() async throws {
        let decoy = try MainInstanceDecoy()
        let file = decoy.root.url.appending(path: ".claude.json")
        let content = "{\"projects\":{\"/Users/nekdo/Projects/cizi\":{\"hasTrustDialogAccepted\":true}}}"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let result = try await cleanup([scratchSlot()], home: decoy.root.url)

        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("záznam po slotu v něm nebyl"))
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
    }

    /// **Na soubor, kterému skript nerozumí, se nesahá** — tatáž pojistka, jakou má zápis
    /// v aplikaci (`ClaudeWorkspaceTrust`). Ztráta je pár záznamů, které v konfiguraci zůstanou
    /// a jdou smazat ručně; přepsaný soubor by byl ztráta cizí práce. Hlásí se to a úklid
    /// pokračuje, protože zbytek slotu se uklidit má.
    @Test("Nečitelná konfigurace se nepřepíše, jen ohlásí")
    func keepsUnreadableClaudeConfig() async throws {
        let decoy = try MainInstanceDecoy()
        let file = decoy.root.url.appending(path: ".claude.json")
        let content = "tohle není JSON"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let result = try await cleanup([scratchSlot()], home: decoy.root.url)

        #expect(result.exitCode == 3)
        #expect(result.standardError.contains("nedá přečíst jako objekt JSON"))
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
        #expect(result.standardOutput.contains("doména v UserDefaults: nebyla"))
        #expect(result.standardOutput.contains("zbývá to, co je vypsané výš"))
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

        // `${CLAUDE_TEMP}` je ta jediná výjimka a **není mimo slot**: je to soubor, který skript sám
        // vyrobil `mktemp`em vedle konfigurace a maže ho, když se přepis nepovede. Že vzniká
        // `mktemp`em, tvrdí řádek níž — bez toho by ta výjimka pustila do výčtu jakoukoli cestu.
        #expect(lines.contains { $0.contains("CLAUDE_TEMP=\"$(mktemp \"${CLAUDE_CONFIG}.prism-XXXXXX\")\"") })
        #expect(lines.contains { $0.contains("CLAUDE_CONFIG=") && $0.contains("${HOME}") })

        let slotScoped = ["${INSTALLED}", "${CACHE}", "${PLIST}", "${BUNDLE_ID}", "${CLAUDE_TEMP}"]
        for line in lines where line.contains("rm -rf") || line.contains("rm -f") || line.contains("defaults delete") {
            #expect(slotScoped.contains { line.contains($0) }, "mazání mimo slot: \(line)")
        }

        // **Záznamy v `~/.claude.json` se nemažou `rm`em, takže je výčet výš nevidí** (#484) —
        // zahazuje je filtr `jq`. Rozsah mu drží dvě proměnné složené ze slotu a **lomítko**
        // v porovnání: bez něj by úklid slotu `a` vzal i záznamy slotu `ab`.
        #expect(lines.contains { $0.contains("CACHE_KEY=\"${CACHE}\"") })
        #expect(lines.contains { $0.contains("CACHE_KEY_REAL=") && $0.contains("${NAME}") })
        #expect(lines.contains { $0.contains("jq --arg root \"${CACHE_KEY}\" --arg real \"${CACHE_KEY_REAL}\"") })
        #expect(lines.contains { $0.contains("startswith($root + \"/\")") })
        #expect(lines.contains { $0.contains("startswith($real + \"/\")") })
        for line in lines where line.contains("with_entries") {
            #expect(line.contains("$root"), "zahazování klíčů mimo kořen slotu: \(line)")
        }

        // `killall` by sestřelil i instanci, se kterou pracuje někdo jiný — a rozdělané review
        // s ní. Ukončuje se Apple eventem na bundle ID, stejně jako v `run.sh`.
        #expect(!lines.contains { $0.contains("killall") })
    }
}
