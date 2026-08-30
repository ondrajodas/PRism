import Darwin
import Foundation

/// Důvěra ke složce v konfiguraci Claude Code (#460).
///
/// **Proč to vůbec existuje.** Interaktivní `claude` se v neznámém adresáři ptá
/// *„Is this a project you created or one you trust?“*. Review sessions na to nenarazí, protože
/// běží s `-p` (`--help` to říká výslovně: v neinteraktivním režimu se dialog přeskakuje), jenže
/// `claude --resume` v zásuvce interaktivní je. A protože **každý pull request dostane vlastní
/// pracovní strom**, byla by to pokaždé nová cesta — dialog by tedy přišel u každého PR znovu
/// a z `▶` by nadobro byla dvoukroková akce.
///
/// **Není to obejití brány, je to postup, na který odkazuje sám `claude`.** V jeho binárce stojí
/// dvakrát věta *„…accept the trust dialog here once interactively, or set
/// `projects[<cesta>].hasTrustDialogAccepted` in `~/.claude.json`“* — tohle je ta druhá cesta,
/// doslova.
///
/// **Zapisuje se do konfigurace cizího nástroje, a to je v tomhle repu nová věc**: do #460 psala
/// aplikace jedině do své cache. Obhajitelné je to tím, **co** se zapisuje: důvěra ke složce,
/// **kterou vyrobila aplikace sama** z repozitáře, jejž si uživatel nakonfiguroval — ne k cizímu
/// adresáři a ne o jedno patro výš, než kam aplikace sahá. Podrobnosti a zamítnuté varianty jsou
/// ve specifikaci.
///
/// **Od #479 se to volá na víc složek než jednu.** Do #479 stačil kořen cache, protože se důvěra
/// dědí z předka — jenže do **git pracovního stromu** se nedědí (změřeno), a strom review je právě
/// to, kam `▶` míří. Který výčet složek to je, rozhoduje `Policy.workspacesToTrust(root:shell:)`;
/// tenhle typ dál umí zapsat **jednu** a nic o tom výčtu neví.
///
/// Za protokolem ze stejného důvodu jako zbytek `Environment/`: je to soubor **mimo naši cache**,
/// takže se v testech nesmí sáhnout na ten skutečný.
protocol WorkspaceTrusting: Sendable {
    /// Zapíše důvěru k té složce, pokud tam ještě není.
    ///
    /// **Nedělá nic, když už je zapsaná** — běžný případ je tedy čisté čtení. Vyhazuje, když se
    /// nepovede číst nebo psát; co s tím, rozhoduje volající.
    func trust(_ directory: URL) async throws
}

/// Proč se důvěra nezapsala.
enum WorkspaceTrustError: Error, Equatable {
    /// Konfigurace Claude Code na disku **není** — nástroj tady ještě neběžel.
    case configurationMissing
    /// Je, ale nedá se přečíst jako objekt JSON. **Nepřepisuje se** (viz `ClaudeWorkspaceTrust`).
    case configurationUnreadable
}

/// Zápis do `~/.claude.json`.
///
/// Tři vlastnosti, na kterých to celé stojí, a každá odpovídá na jinou otázku „co když“:
///
/// 1. **Nikdy nepřepíše, čemu nerozumí.** Když soubor není nebo se nedá přečíst jako objekt,
///    skončí to chybou a **na disk se nesáhne**. Ztráta je jeden dialog navíc; rozbitá
///    konfigurace by byla ztráta cizí práce.
/// 2. **Zachovává, co v souboru je.** Mění se jedna hodnota v jednom projektu, zbytek se přenese
///    tak, jak byl. Přeskládání klíčů je jediná viditelná změna, kterou to udělá — JSON je
///    neuspořádaný a `JSONSerialization` pořadí nezachovává.
/// 3. **Zapisuje atomicky.** Dočasný soubor ve stejné složce a `replaceItemAt`, takže při pádu
///    uprostřed zůstane na disku původní verze, ne půlka. `replaceItemAt` navíc přenese původní
///    práva (`0600`), takže se soubor nezpřístupní.
struct ClaudeWorkspaceTrust: WorkspaceTrusting {
    /// Kde konfigurace leží. Injektovatelné, aby testy nesáhly na tu skutečnou.
    let configuration: URL

    static let inHomeDirectory = ClaudeWorkspaceTrust(
        configuration: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
    )

    /// Klíč, pod kterým si `claude` pamatuje projekt.
    ///
    /// **Rozvinutá cesta, ne ta, kterou dostaneme** — změřeno: nad `/tmp/x` hlásí `claude`
    /// workspace `/private/tmp/x`, takže záznam pod nerozvinutou cestou by se nikdy netrefil.
    ///
    /// **A rozvíjí to `realpath`, ne `resolvingSymlinksInPath`**, protože ta Foundationovská cesta
    /// `/tmp` ani `/var` schválně nerozvíjí (změřeno: vrátí `/tmp`) — a přesně tyhle dva prefixy
    /// jsou na macOS symlinky. Na kořeni cache to dnes nic nemění, ale domovská složka umí ležet
    /// za symlinkem a záznam by se pak minul potichu.
    ///
    /// Když cesta na disku není, vrací se **tak, jak přišla**: `realpath` na neexistující soubor
    /// selže a hádat za něj se nemá čím.
    static func key(for directory: URL) -> String {
        let path = directory.path(percentEncoded: false)
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func trust(_ directory: URL) async throws {
        try await Task.detached(priority: .utility) {
            let data: Data
            do {
                data = try Data(contentsOf: configuration)
            } catch {
                throw WorkspaceTrustError.configurationMissing
            }
            guard
                let decoded = try? JSONSerialization.jsonObject(with: data),
                var root = decoded as? [String: Any]
            else {
                throw WorkspaceTrustError.configurationUnreadable
            }

            let key = Self.key(for: directory)
            var projects = root["projects"] as? [String: Any] ?? [:]
            var project = projects[key] as? [String: Any] ?? [:]
            // **Hotová důvěra se nepřepisuje.** Běžný případ je tím pádem čisté čtení, což je
            // jediná ochrana, kterou proti souběžnému zápisu `claude` samotného máme: okno, ve
            // kterém se dá o cizí změnu přijít, je jedno jediné zapsání za život té složky.
            //
            // **Zapsané `false` se naopak přepsat smí, a je to rozhodnutí, ne nedopatření** (#479).
            // Je to složka v naší cache, kterou aplikace sama vyrobila — a `false` si tam `claude`
            // zapisuje **sám** při každém běhu nad složkou, kterou v konfiguraci ještě nemá
            // (změřeno). Není to tedy odpověď člověka „nevěřím“, ale výchozí hodnota záznamu.
            // U cizích projektů se to netýká ničeho: sahá se jedině na klíč, který jsme dostali.
            if project["hasTrustDialogAccepted"] as? Bool == true { return }
            project["hasTrustDialogAccepted"] = true
            projects[key] = project
            root["projects"] = projects

            let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
            let temporary = configuration.deletingLastPathComponent()
                .appending(path: ".claude.json.prism-\(UUID().uuidString)")
            try updated.write(to: temporary, options: .atomic)
            // Po neúspěchu se dočasný soubor **uklidí**: leží v domovské složce a zůstat by tam
            // neměl ani jeden. `replaceItemAt` ho při úspěchu spotřebuje, takže tohle je jediná
            // cesta, kterou se dá zapomenout.
            do {
                // `replaceItemAt` přenese práva a atributy původního souboru — `~/.claude.json` má
                // `0600` a nový soubor by ho jinak zpřístupnil.
                _ = try FileManager.default.replaceItemAt(configuration, withItemAt: temporary)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }.value
    }
}
