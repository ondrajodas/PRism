import Foundation

/// Tělo a argumenty jednoho odeslání. Čisté funkce, žádné I/O — testuje se bez `gh`.
enum PublishRequest {
    /// Payload pro `POST /pulls/{n}/reviews`.
    ///
    /// **Jedno volání se vším**: `event`, `body`, `commit_id` a `comments[]`. Změřeno u #62,
    /// že je atomické — jeden neplatný komentář shodí celé review a na PR nezůstane nic.
    /// Právě proto se skládá celý payload, ne komentář po komentáři.
    struct Payload: Encodable, Equatable {
        let commitID: String
        let body: String
        let event: String
        let comments: [Comment]

        struct Comment: Encodable, Equatable {
            let path: String
            let line: Int
            let side: String
            /// Rozsah řádků (#110). U jednořádkového komentáře **oba `nil`**, takže v payloadu
            /// nejsou vůbec — je to tentýž tvar, který prošel u #62 a #67.
            let startLine: Int?
            let startSide: String?
            let body: String

            enum CodingKeys: String, CodingKey {
                case path, line, side, body
                case startLine = "start_line"
                case startSide = "start_side"
            }
        }

        enum CodingKeys: String, CodingKey {
            case commitID = "commit_id"
            case body, event, comments
        }
    }

    /// `nil` = z draftu se payload složit nedá.
    ///
    /// Chybí jedině verdikt: `event` je v API povinný a hádat ho za člověka znamená odeslat
    /// něco jiného, než chtěl. Prázdné tělo naopak vadit nemusí — schválení bez prózy je
    /// plnohodnotné review (v datech z #63 čtvrtina vzorku).
    static func payload(for draft: ReviewDraft) -> Payload? {
        guard let verdict = draft.verdict else { return nil }
        return Payload(
            commitID: draft.headSha,
            body: draft.body,
            event: verdict.rawValue,
            comments: draft.comments.map {
                Payload.Comment(
                    path: $0.path,
                    line: $0.line,
                    // Strana se posílá tak, jak ji chce API — `RIGHT`/`LEFT`. Bez ní by
                    // komentář k odebranému řádku sedl na jiný kód.
                    side: $0.side.rawValue,
                    // Rozsah jde jako `start_line`/`start_side` (změřeno u #110). Konec je
                    // `line`/`side` výš, takže bublina i payload míří na tentýž řádek.
                    startLine: $0.startLine,
                    startSide: $0.startSide?.rawValue,
                    body: $0.body
                )
            }
        )
    }

    /// Argumenty pro `gh api`. Payload jde souborem, protože `ProcessRunning` neumí stdin —
    /// a přidávat mu metodu jen kvůli tomuhle by ji musely dopsat všechny fake implementace
    /// v testech, tedy stejná úvaha, kvůli které je streamování vlastní protokol.
    static func arguments(for pr: PRIdentifier, payload file: URL) -> [String] {
        [
            "api", "repos/\(pr.repo)/pulls/\(pr.number)/reviews",
            "-X", "POST",
            "--input", file.path(percentEncoded: false),
        ]
    }

    static func encoded(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Dá se tenhle text odeslat jako komentář?
    ///
    /// **Prázdné tělo GitHub tiše spolkne** — změřeno v sandboxu u odpovědi do vlákna (#73):
    /// mutace vrátí `comment: null`, exit kód **nula** a ve vlákně nic nepřibude. Bez téhle
    /// kontroly by aplikace hlásila „odesláno“ nad odpovědí, která nikdy nevznikla. Text se
    /// posílá **netrimovaný** (odsazení v ukázce kódu je součást zprávy), kontroluje se
    /// trimovaný.
    ///
    /// Sdílené odpovědí do vlákna i komentářem pod PR (#216) — je to jedna otázka a dvě
    /// kopie by se rozešly zrovna v tom, co která považuje za prázdné.
    static func isSendable(_ body: String) -> Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
