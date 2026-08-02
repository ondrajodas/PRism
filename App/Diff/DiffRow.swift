import Foundation

/// Jeden řádek diffu tak, jak se kreslí.
///
/// Diff se do líného seznamu skládá **rozbalený na řádky**, ne po hunkách. Hunk jako
/// jedna buňka se po zvětšení okna překreslil jen zčásti a mezi hlavičkami zůstala
/// prázdná místa — buňka, kterou líný seznam vytvořil při jiné šířce, se sama od sebe
/// nepřeměří. Řádek jako vlastní buňka tenhle problém nemá.
enum DiffRow: Identifiable {
    case hunk(String, DiffHunk)
    case line(String, DiffLine)
    /// Věta místo obsahu — u binárky nebo u souboru beze změny obsahu.
    case note(String, String)

    /// Identita v rámci **celého** diffu, ne jen souboru: skáče se na ni z panelu nálezů,
    /// takže se dvě různá místa nesmí trefit do jedné.
    var id: String {
        switch self {
        case .hunk(let id, _), .line(let id, _), .note(let id, _): id
        }
    }

    static func rows(of file: FileDiff) -> [DiffRow] {
        if file.isBinary {
            return [.note(id(of: file, at: 0), "Binární soubor — obsah se nezobrazuje.")]
        }
        if file.hunks.isEmpty {
            return [.note(id(of: file, at: 0), "Beze změny obsahu.")]
        }

        var rows: [DiffRow] = []
        for hunk in file.hunks {
            rows.append(.hunk(id(of: file, at: rows.count), hunk))
            for line in hunk.lines {
                rows.append(.line(id(of: file, at: rows.count), line))
            }
        }
        return rows
    }

    /// Kam v diffu ukazuje nález — id řádku, na který se dá odscrollovat.
    ///
    /// Když se řádek najít nedá (nález bez čísla nebo na řádku mimo hunky), vrací se
    /// **soubor**: reviewer čte celý pracovní strom, ne jen diff, takže umí nahlásit
    /// řádek, který se nezměnil. Odskočit aspoň na soubor je pořád lepší než nic.
    static func anchor(in diff: Diff, file path: String, line: Int?) -> String? {
        guard let file = diff.files.first(where: { $0.newPath == path || $0.oldPath == path })
        else { return nil }
        guard let line else { return file.id }

        let row = rows(of: file).first { row in
            guard case .line(_, let content) = row else { return false }
            return content.newNumber == line
        }
        return row?.id ?? file.id
    }

    /// Řádky vycházejí z `file.id`, na kterém visí i sekce souboru — proto se na soubor
    /// dá skočit stejnou cestou jako na řádek a identity se mezi soubory nekříží.
    private static func id(of file: FileDiff, at index: Int) -> String {
        "\(file.id)|\(index)"
    }
}
