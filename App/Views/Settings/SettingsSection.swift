import Foundation

/// Stránky okna nastavení (#177).
///
/// Do #177 to byly tři záložky, ze kterých `Obecné` nesla osm sekcí — zdroje, režim, jazyk,
/// pohled na diff, odesílání, dva editory skillů, blokující kategorie a hrst čísel běhu. Hledalo
/// se v ní scrollováním a nedalo se na ni odkázat.
///
/// Dělení je podle **otázky, na kterou se odpovídá**, ne podle typu ovládacího prvku: `Odesílání`
/// je vlastní stránka, i když je to jeden přepínač a jeden seznam, protože je to jediné místo,
/// kde se rozhoduje, jestli z aplikace něco může odejít.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case sources
    case review
    case diff
    case publishing
    case notifications
    case repositories
    case runtime
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sources: "Zdroje PR"
        case .review: "Review a skilly"
        case .diff: "Diff"
        case .publishing: "Odesílání"
        case .notifications: "Notifikace"
        case .repositories: "Repozitáře"
        case .runtime: "Běh"
        case .system: "Systém"
        }
    }

    var symbol: String {
        switch self {
        case .sources: "line.3.horizontal.decrease.circle"
        case .review: "sparkles"
        case .diff: "rectangle.split.2x1"
        case .publishing: "arrow.up.circle"
        case .notifications: "bell"
        case .repositories: "folder"
        case .runtime: "gauge.with.dots.needle.33percent"
        case .system: "desktopcomputer"
        }
    }

    /// Skupina v seznamu. Odděluje **co se hlídá** od **jak se to dělá** a od **provozu** —
    /// bez nadpisů je osm položek pod sebou jen seznam.
    var group: Group {
        switch self {
        case .sources, .review, .diff: .work
        case .publishing, .notifications: .output
        case .repositories, .runtime, .system: .setup
        }
    }

    enum Group: String, CaseIterable, Identifiable, Sendable {
        case work
        case output
        case setup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .work: "Co se hlídá"
            case .output: "Co jde ven"
            case .setup: "Prostředí"
            }
        }

        var sections: [SettingsSection] {
            SettingsSection.allCases.filter { $0.group == self }
        }
    }
}
