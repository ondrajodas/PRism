import Foundation

// MARK: - Otevření souboru v editoru (#530)

extension AppStore {
    /// V čem se otevírají soubory. `nil` = **tlačítko se nikde nekreslí.**
    var externalEditor: ExternalEditor? { configuration.global.externalEditor }

    /// Klik na `Otevřít v <editoru>` v hlavičce souboru nebo na kartě nálezu.
    ///
    /// Cesta má **pět zastávek a žádná se nedá přeskočit**:
    ///
    /// 1. **Zvolený editor.** Bez něj se tlačítko nekreslí, takže sem se nedojde — a kdyby přece,
    ///    nesmí se otevřít „něco“.
    /// 2. **Strom v cache** (`Policy.editorTree`), ověřený tím, že složka doopravdy existuje:
    ///    eviction ji umí sebrat a adresa do smazané složky by editor otevřel prázdný.
    /// 3. **Hranice cache** (`CacheFile.refusal`) — viz níž, je to jádro celé téhle akce.
    /// 4. **Existence souboru.** Smazaný soubor je v diffu vidět, na disku po něm nezůstalo nic;
    ///    bez téhle zastávky by editor otevřel prázdné okno a vypadalo by to jako prázdný soubor.
    /// 5. **Systém adresu převzal.** `NSWorkspace.open` vrací `false`, když schéma nemá kdo
    ///    obsloužit — a spolknout to nejde, protože výsledek téhle akce je **mimo okno**.
    ///
    /// Šestá je **pojistka, ne zastávka**: složení adresy (`Policy.editorURL`). Selhat prakticky
    /// nemá čím, ale **vlastní větu má taky** — sáhnout u ní po hlášce o cestě mimo cache by
    /// znamenalo, že tu jednu důležitou větu řekne i něco, co se nestalo.
    ///
    /// **`CacheFile.refusal`, ne `isInsideCache`, a je to vědomá odchylka od zadání #530.**
    /// `isInsideCache` je verdikt pro **mazání**, které přes odkaz smaže odkaz; tohle je čtení
    /// a psaní, takže platí ta přísnější dvojice — symbolický odkaz **na samotném souboru** by
    /// editor otevřel jeho **cíl**, a ten smí ležet kdekoli. Tvrdá podmínka č. 3 by tím padla
    /// nejtišší možnou cestou: cesta v cache, editor v uživatelově klonu. Je to tatáž úvaha (a
    /// tatáž volba) jako u zásuvky s terminálem.
    ///
    /// **Nic se nespolkne.** Každá zastávka má vlastní větu v `editorFailure` — obecné
    /// „nepodařilo se otevřít“ by slilo „soubor tu není“ s „mířili jsme mimo cache“, a to druhé
    /// je jediný stav, u kterého se má někdo zarazit.
    func openInEditor(file path: String, line: Int?, of pr: PRIdentifier) async {
        editorFailure = nil
        guard let editor = externalEditor, let opener = editorOpener else { return }
        guard let tree = await editorTree(for: pr) else {
            editorFailure = Policy.editorNoWorktreeNote
            return
        }
        // `standardizedFileURL` **před** kontrolou hranice, ne po ní: `..` uprostřed cesty
        // (přejmenování v diffu, ručně složená cesta z nálezu) by jinak zůstalo v adrese a hranici
        // by řešilo až rozbalování symlinků uvnitř `contains`. Standardizace je levná a dělá tu
        // otázku jednoznačnou.
        let target = tree.appending(path: path).standardizedFileURL
        if let refusal = CacheFile.refusal(for: target, in: cacheLayout) {
            editorFailure = Policy.editorRefusalNote(refusal, path: path)
            return
        }
        guard await existingFile(target) else {
            editorFailure = Policy.editorMissingFileNote(path)
            return
        }
        guard let url = Policy.editorURL(editor, file: target, line: line) else {
            editorFailure = Policy.editorAddressNote(editor, path: path)
            return
        }
        guard await opener.open(url) else {
            editorFailure = Policy.editorRefusedBySystemNote(editor)
            return
        }
    }

    /// Ze kterého stromu se otevírá — strom pro srovnání větve, jinak ten od posledního review.
    ///
    /// Obojí se ověřuje **existencí složky, ne stavem v panelu**: `-sync` po sobě zahodí
    /// `Zahodit rebase`, strom review sebere eviction, a obojí se může stát z druhého okna.
    /// Rozhodnutí, který z nich vyhraje, je v `Policy` — tady se jen sahá na disk.
    private func editorTree(for pr: PRIdentifier) async -> URL? {
        Policy.editorTree(
            sync: await existingDirectory(cacheLayout.syncWorktree(for: pr)),
            review: await existingDirectory(timelines(for: pr).compactMap(\.worktree).last)
        )
    }

    /// Je na té cestě soubor? **Mimo hlavní vlákno**, ze stejného důvodu jako `existingDirectory`.
    ///
    /// Složka se počítá za „není“: otevřít adresář v editoru sice jde, ale tlačítko slibuje
    /// soubor na řádku, a otevřený projekt místo souboru je odpověď na jinou otázku.
    private func existingFile(_ url: URL) async -> Bool {
        await Task.detached {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            return exists && !isDirectory.boolValue
        }.value
    }
}
