import Foundation

/// Editor, ve kterém se otevírá soubor z kopie v cache (#530).
///
/// **Výčet, ne cesta k binárce ani volný text.** Otevírá se URL schématem, které si editor
/// zaregistroval v systému, takže aplikace nepotřebuje vědět, kde je nainstalovaný — a hlavně
/// nespouští podproces. Volný text („čím otevírat“) by znamenal, že se do `NSWorkspace` dostane
/// libovolné schéma z `config.json`; tři vyjmenované hodnoty jsou naopak něco, co jde otestovat
/// výčtem.
///
/// **`nil` v konfiguraci znamená „tlačítko se nekreslí“**, ne „ber výchozí“. Který editor člověk
/// používá, se z ničeho odvodit nedá a hádat Xcode jen proto, že je to macOS, by znamenalo
/// tlačítko, které u poloviny lidí otevře něco cizího.
enum ExternalEditor: String, Codable, CaseIterable, Identifiable, Sendable {
    case xcode
    case vscode
    case cursor

    var id: String { rawValue }

    /// Jméno, jak ho zná systém — v nastavení a v hlášce o odmítnuté adrese.
    var title: String {
        switch self {
        case .xcode: "Xcode"
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        }
    }

    /// Šestý pád **i s předložkou**, protože ta se u jednoho z nich mění: `ve VS Code` proti
    /// `v Xcodu` a `v Cursoru`. Skládat `"v " + title` by vyrobilo „v VS Code“ — a popisek
    /// tlačítka je to jediné, co u téhle akce člověk čte.
    var locative: String {
        switch self {
        case .xcode: "v Xcodu"
        case .vscode: "ve VS Code"
        case .cursor: "v Cursoru"
        }
    }
}
