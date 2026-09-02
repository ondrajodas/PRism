import SwiftUI

/// Stránka `Zdroje PR` (#177) — odkud se seznam bere a **čí ty pull requesty jsou** (#389).
///
/// Loginy patří sem, ne ke skillům: je to identita, tedy tatáž otázka, na kterou odpovídají
/// zdroje. Vlastní sekce „ostatní“ by z okna udělala smetiště, ve kterém se hledá podle toho, kdy
/// co přibylo.
struct SourcesSettingsView: View {
    @Bindable var settings: SettingsModel
    /// Login z `gh api user`. Prázdný = ještě se nezjistil; **není to totéž jako prázdný seznam
    /// vlastních loginů** a v okně se to nesmí slít.
    let viewer: String
    /// Seznamy repozitářů organizací (#532) — sekce `Organizace k prohledávání` níž.
    let catalog: RepositoryCatalog
    let time: any TimeSource

    var body: some View {
        Form {
            Section {
                SourceListEditor(sources: $settings.draft.global.sources)
            } header: {
                Text("Zdroje")
            } footer: {
                Text("Search dotazy pro `gh search prs`. Výsledky se slévají a deduplikují.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                account
                StringListEditor(
                    items: $settings.draft.global.ownLogins,
                    itemLabel: "Login",
                    placeholder: "github-actions[bot]",
                    addLabel: "Přidat login"
                )
            } header: {
                Text("Moje loginy")
            } footer: {
                Text("Rozhoduje to, **čí PR je čí**: co je moje, jde do vlastní fronty a nabídne se u toho merge; ostatní čekají na review. Přihlášený účet se bere z `gh api user` a nepíše se — vypisují se jen loginy, které se od něj liší, typicky agent s vlastním účtem nebo bot. Prázdný seznam je běžný stav: kdo pushuje pod svým `gh`, druhý login nemá.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                OrganizationListEditor(
                    organizations: $settings.draft.global.searchOrganizations,
                    catalog: catalog,
                    refreshStale: { Task { await catalog.refreshStale(organizations: organizations) } },
                    refreshAll: { Task { await catalog.refresh(organizations: organizations) } },
                    now: time.now
                )
            } header: {
                Text("Organizace k prohledávání")
            } footer: {
                Text("Seznam repozitářů těchhle organizací se drží v cache, aby se dal prohledávat bez dotazu na GitHub — dotažení je nad velkou organizací věc desítek sekund. Obnovuje se **jednou denně, dopsáním organizace nebo tlačítkem**, nikdy při psaní. **Není to zdroj fronty**: co se tahá pravidelně a počítá se do karet, odznaku a automatu, říkají zdroje výš.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Dotáhne, co v cache chybí nebo je starší než den. **Při otevření stránky, ne na tik** —
        // je to desítky sekund práce nad seznamem, do kterého se nikdo nedívá, dokud sem nepřijde.
        .task { await catalog.refreshStale(organizations: organizations) }
    }

    /// Organizace tak, jak jsou zrovna ve formuláři — ne z uložené konfigurace: mezi dopsáním
    /// řádku a zápisem na disk je zpoždění (`SettingsModel`), takže by se čerstvě napsaná
    /// organizace nedotáhla.
    private var organizations: [String] {
        settings.draft.global.searchOrganizations
    }

    /// Přihlášený účet — **řádek ke čtení, ne pole**. Nad seznamem schválně: bez něj by prázdný
    /// seznam vypadal jako „nevím, kdo jsem“, což je jiný stav (a v něm je každý PR cizí).
    @ViewBuilder private var account: some View {
        let account = Policy.viewerAccount(login: viewer)
        // Poznámka je **pod řádkem, ne ve sloupci s hodnotou**: v užším okně (509 bodů obsahové
        // části při `minWidth`) si dvouřádková hodnota vytlačí popisek na vlastní řádek a řádek
        // se rozpadne. Pod řádkem se zalomí, kam potřebuje, a popisek zůstane vedle hodnoty.
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Přihlášený účet") {
                Text(verbatim: account.label)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(account.note == nil ? .primary : .secondary)
                    .textSelection(.enabled)
            }
            if let note = account.note {
                Text(verbatim: note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

}
