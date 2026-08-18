import SwiftUI

/// Záložka `Notifikace` v okně nastavení (#86).
///
/// **Vlastní záložka, ne sekce v `Obecné`.** Ta záložka je dlouhá (zdroje, režim, jazyk,
/// pohled na diff, odesílání, tři editory seznamů, běh) a notifikace by v ní byly šestý pruh
/// přepínačů, který se najde scrollováním. Notifikace jsou navíc jediná část aplikace, která
/// si sahá na systémové oprávnění, takže mají o čem mluvit samy za sebe.
///
/// Zapisuje se sem stejně jako do zbytku formuláře — odloženě, do téhož `config.json`, viz
/// `SettingsModel`.
struct NotificationSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Posílat notifikace", isOn: $settings.draft.global.notifications.isEnabled)
            } footer: {
                // Říká, co se stane s oprávněním, protože to je jediná část, kam aplikace
                // nedosáhne — a je to zadání #86: s vypnutými notifikacemi se nemá ptát.
                Text("Aplikace dá vědět, i když se do ní nikdo nedívá; klik na notifikaci vybere ten pull request. O systémové povolení si řekne teprve u první notifikace, takže s vypnutým přepínačem se nezeptá vůbec. Když ho macOS zakáže, je to vidět ve stavovém řádku dole.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Jednotlivé události se **schovají**, když je hlavní vypínač vypnutý: pět
            // zakázaných přepínačů pod vypnutým vypínačem je pět řádků, které nic neříkají.
            // U tlačítek v okně review je to obráceně (zakázané zůstávají a řeknou důvod), ale
            // tam ten důvod není o řádek výš — tady je.
            if settings.draft.global.notifications.isEnabled {
                Section {
                    Toggle("Nový PR k review", isOn: $settings.draft.global.notifications.newPullRequest)
                    Toggle("Review s nálezy", isOn: $settings.draft.global.notifications.findings)
                    Toggle("Čisté review", isOn: $settings.draft.global.notifications.clean)
                    Toggle("Review se nepovedlo", isOn: $settings.draft.global.notifications.failure)
                    // Pátá událost (#335), a **jediná o vlastních PR** — proto stojí pod třemi
                    // o review, ne mezi nimi: ty čtyři jsou odpověď na review request, tahle je
                    // opačný směr.
                    Toggle("Ozval se někdo na mém PR", isOn: $settings.draft.global.notifications.activity)
                } header: {
                    Text("Co hlásit")
                } footer: {
                    // Text říká, **co v které notifikaci uvidím**, ne jen že existuje: podle
                    // toho se rozhoduje, co vypnout. `Čisté review` má vysvětlení navíc, protože
                    // je to nejčastější hláška u automatického režimu a nejmenší informace.
                    Text("`Review s nálezy` nese počet a to, kolik z nich blokuje — a taky běh, který se nevešel do limitu, ale nálezy stihl. `Čisté review` je zpráva, že nezbylo nic k řešení; u ručně spuštěného běhu je to ta odpověď, na kterou se čeká, u automatu s dvaceti běhy denně nejčastější a nejmenší informace. `Review se nepovedlo` pokrývá spadlou session, selhanou pracovní kopii a běh, který nedoběhl a nic nenahlásil. `Ozval se někdo na mém PR` je jediná hláška o vlastních PR: komentář kolegy, odpověď ve vlákně nebo odeslané review včetně Copilotova — o svém vlastním komentáři se nedozvíš. Diskuze vlastních PR se přitom hlídá jen tam, kde se od minule něco změnilo, a nejvýš po pěti minutách. Platí globálně, ne per repo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
