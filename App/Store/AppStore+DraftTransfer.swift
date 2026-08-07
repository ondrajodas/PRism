import Foundation

/// Přenesení rozdělaného review na nový commit (#69).
///
/// Vlastní soubor, protože je to samostatný **tok s vlastním stavem rozhodnutí**
/// (`transferChoices`), který se drží jen po dobu potvrzování.
extension AppStore {
    /// Stavy kotev proti **aktuálnímu** diffu — z nich se skládá seznam v potvrzení přenesení.
    ///
    /// Prázdné, když není co přenášet: žádný draft, nebo není načtený diff (bez něj by se
    /// rozhodovalo naslepo).
    func draftAnchorStates(for pr: PRIdentifier) -> [DraftAnchorCheck] {
        guard let draft = drafts[pr], case .loaded(let diff, _) = diffStates[pr] else { return [] }
        return draft.comments.map { DraftAnchorCheck(comment: $0, state: Policy.anchorState(of: $0, in: diff)) }
    }

    /// Dá se draft přenést na nový commit? Jen když je zastaralý a je proti čemu ho kontrolovat.
    func canTransferDraft(for pr: PRIdentifier) -> Bool {
        guard isDraftStale(for: pr), head(of: pr) != nil else { return false }
        guard case .loaded = diffStates[pr] else { return false }
        return true
    }

    /// Přenese draft na hlavu PR podle rozhodnutí z potvrzení.
    ///
    /// Nový `headSha` se nastavuje **až tady**, tedy až po tom, co člověk viděl, co se s kterou
    /// kotvou stane — dokud se draft nepřenesl, musí zůstat zastaralý a nedat se odeslat. Draft,
    /// ze kterého by nic nezůstalo (všechno smazané), se **smaže**: „draft existuje“ musí znamenat
    /// „je co poslat“.
    @discardableResult
    func transferDraft(for pr: PRIdentifier, choices: [UUID: DraftTransferChoice] = [:]) -> ReviewDraft? {
        guard let draft = drafts[pr], let head = head(of: pr),
              case .loaded(let diff, _) = diffStates[pr]
        else { return nil }

        let transferred = Policy.transferring(
            draft,
            to: diff,
            head: head,
            in: pr.repo,
            choices: choices
        )
        // Přes `mutateDraft`, ne zápisem do mapy: pravidlo „prázdný draft se maže“ i zápis na disk
        // mají zůstat na jednom místě. Druhá kopie by se s ním časem rozešla.
        mutateDraft(for: pr) { $0 = transferred }
        // Vrací se **přenesený** draft, i když z něj v mapě nic nezůstalo: potvrzení odeslání si
        // z něj udělá nový snímek, a prázdný draft se pozná na tom, že v něm nic není.
        return transferred
    }

    /// Přepíše text komentáře. **Prázdný text komentář zahodí.**
    ///
    /// Prázdné komentáře vznikají běžně (kliknu na „komentovat“ a rozmyslím si to) a GitHub
    /// je odmítne — a protože je odeslání atomické, padlo by s nimi celé review. Nechat je
    /// ležet v draftu znamená hledat, proč se nedá odeslat.
    func updateDraftComment(_ id: UUID, body: String, for pr: PRIdentifier) {
        mutateDraft(for: pr) { draft in
            guard let index = draft.comments.firstIndex(where: { $0.id == id }) else { return }
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.comments.remove(at: index)
            } else {
                draft.comments[index].body = body
            }
        }
    }

    func removeDraftComment(_ id: UUID, for pr: PRIdentifier) {
        mutateDraft(for: pr) { $0.comments.removeAll { $0.id == id } }
    }

    func setDraftBody(_ body: String, for pr: PRIdentifier) {
        mutateDraft(for: pr) { $0.body = body }
    }

    /// Vybere verdikt, nebo volbu zruší (`nil`).
    ///
    /// Tudy chodí **jen moje volba** — tedy klik v panelu. Návrh z nálezů (#114) se tímhle
    /// nezapisuje: platí, dokud si člověk nevybere, a počítá ho `effectiveVerdict(for:)`.
    /// Zrušená volba proto nekončí u „nevybráno“, ale u návrhu, když je z čeho.
    func setDraftVerdict(_ verdict: ReviewDraft.Verdict?, for pr: PRIdentifier) {
        mutateDraft(for: pr) { $0.verdict = verdict }
    }

    /// Přidá do těla review položku s odkazem na kód.
    ///
    /// Používá se pro nález mimo diff a pro řádek, který komentář neunese — tam GitHub
    /// řádkový komentář nepustí a odmítne s ním celé review (změřeno u #62).
    ///
    /// Odkaz míří na commit, **proti kterému je draft psaný**, ne na aktuální hlavu PR: draft,
    /// který se s hlavou rozešel, se neodešle (banner), ale odkaz v něm pořád ukazuje na kód,
    /// ke kterému se ta věta psala.
    func appendDraftBodyItem(text: String, path: String?, line: Int?, for pr: PRIdentifier) {
        mutateDraft(for: pr) { draft in
            let link = path.flatMap {
                Policy.permalink(to: $0, line: line, in: pr.repo, at: draft.headSha)
            }
            draft.body = Policy.appendingBodyItem(
                Policy.bodyItem(text: text, link: link),
                to: draft.body
            )
        }
    }
}
