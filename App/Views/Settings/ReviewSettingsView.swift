import SwiftUI

/// Stránka `Review a skilly` (#177).
///
/// Tři věci, které spolu souvisí a do #177 byly ve třech různých sekcích jedné dlouhé záložky:
/// **kdy** se review pouští, **co** se pouští a **co z toho je vážné**.
struct ReviewSettingsView: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Výchozí režim", selection: $settings.draft.global.mode) {
                    Text("Manuální").tag(ReviewMode.manual)
                    Text("Automatický").tag(ReviewMode.automatic)
                }
                .pickerStyle(.radioGroup)

                // Jazyk patří sem, ne mezi hodnoty běhu: je to spolu s režimem to, co se
                // u jednotlivých rep mění nejčastěji, a v obou případech je globální
                // hodnota jen výchozí.
                Picker("Jazyk nálezů", selection: $settings.draft.global.findingsLanguage) {
                    ForEach(FindingsLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language.displayName).tag(language)
                    }
                }

                // Sem, ne na stránku `Běh` (#320): je to třetí věc o **spuštěném** review, kterou
                // si repo smí přebít — vedle režimu a jazyka nálezů. Čísla na stránce `Běh` jsou
                // proti tomu vlastnost stroje a člověka (interval, souběh, rozpočet cache)
                // a override nemají.
                ReviewTimeoutField(
                    label: "Časový limit běhu (min)",
                    minutes: $settings.draft.global.reviewTimeoutMinutes
                )

                // Sem, ne na stránku `Běh` (#517): je to čtvrtá věc o **spuštěném** review, kterou
                // si repo smí přebít — vedle režimu, jazyka a limitu. A je to rozhodnutí o tom,
                // *nad čím* se běží, tedy tatáž otázka jako režim o pár řádků výš.
                Toggle("Po pushi review jen přírůstku", isOn: $settings.draft.global.incrementalAfterPush)
            } header: {
                Text("Režim review")
            } footer: {
                Text("Platí pro repa, která si neřeknou o jiný. Manuální čeká na tlačítko, automatický spustí review, jakmile se PR objeví v seznamu. Jazyk se týká textu nálezů; `category` zůstává vždycky anglicky, protože je to slug, na který se váže blokující sada. Limit platí na jednu session — tedy na každý skill zvlášť a stejně tak na kontrolu nálezů. Zabitý běh si nechá, co stihl nahlásit. Rozsah je \(ReviewTimeout.minimumMinutes)–\(ReviewTimeout.maximumMinutes) min a „bez limitu“ mezi volbami není: je to jediná pojistka proti session, která se zacyklí a utrácí. Přírůstek znamená, že po pushi dostane reviewer jen diff nových commitů a k tomu nálezy z minula — řekne, které trvají, a hlásí jen nové. Staré nálezy se **neztrácejí**: přenesou se na novou hlavu s odznakem. V prvním kole a po force pushi bez společné historie se jde na celý diff a v tabu `Průběh` je vidět proč.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            agent

            autoDraft

            brief

            // Vlastní sekce, ne řádek v `Režim review` (#519): tamty čtyři hodnoty si repo smí
            // přebít, tahle **ne** — kdy chci mít na stroji ticho, z repozitáře neplyne. Sekce se
            // svým vlastním vysvětlením je jediné místo, kde se ten rozdíl dá říct.
            Section {
                Toggle("Velké PR odložit do tichých hodin", isOn: $settings.draft.global.quietHours.isEnabled)
                SettingsNumberField(
                    label: "Práh (změněných řádků)",
                    value: $settings.draft.global.quietHours.lineThreshold,
                    range: 1...100_000,
                    step: 100
                )
                SettingsHourField(
                    label: "Od (hodin)",
                    hour: $settings.draft.global.quietHours.startHour
                )
                SettingsHourField(
                    label: "Do (hodin)",
                    hour: $settings.draft.global.quietHours.endHour
                )
            } header: {
                Text("Tiché hodiny")
            } footer: {
                Text("Platí **jen na automat** — ruční `Spustit review` odklad nezná a PR, který mám otevřený, se neodkládá. Ostatní PR nad prahem se mimo tiché hodiny odloží na nejbližší začátek okna; v tabu `Průběh` je vidět kdy a tlačítko `Pustit teď` je pustí hned (ručně, tedy mimo denní limit). Práh se bere z hlavičky PR (`+` a `−` dohromady), ne z diffu. Okno smí přecházet přes půlnoc (`22`–`6`); stejná hodnota na obou stranách odklad vypne, protože prázdné okno je čitelnější než ticho pořád. Denní limit ani strop útraty tím neobchází — odklad mění, **kdy** se session utratí, ne kolik jich bude. Odložené běhy přežijí restart: co se nestihlo v noci, pustí první tik po startu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                StringListEditor(
                    items: $settings.draft.global.skills,
                    itemLabel: "Skill",
                    placeholder: "code-review:code-review",
                    addLabel: "Přidat skill"
                )
            } header: {
                Text("Skilly")
            } footer: {
                Text("Každý skill je jedna headless session. Repo si sadu může přebít.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LanguageSkillsEditor(
                    skillsByLanguage: $settings.draft.global.skillsByLanguage,
                    globalFallback: settings.draft.global.skills
                )
            } header: {
                // „Jazyk“ samotné se plete s jazykem, ve kterém reviewer píše nálezy
                // (#52) — proto všude „programovací jazyk“, i když je to delší.
                Text("Skilly podle programovacího jazyka")
            } footer: {
                Text("Při review se z obsahu repa pozná, čím je psané, a použije se sada odsud. Rozhoduje to, **které skilly se spustí** — ne jazyk, ve kterém reviewer píše nálezy. Jazyk, který tu není, bere sadu výš.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Pod sadami skillů, ne mezi ně (#281): je to totéž rozhodnutí („co se pustí a co
            // tomu řekneme“), kdežto blokující kategorie o kus níž jsou už o tom, co z výsledku
            // je vážné.
            Section {
                ReviewPromptEditor(stored: $settings.draft.global.reviewPrompt)
            } header: {
                Text("Prompt review")
            } footer: {
                Text("Zástupné texty dosadí aplikace při spuštění. Co je pod zámkem, drží sběr nálezů — připojí se i tehdy, když si to někdo ze šablony smaže; bez `ReportFindings` by reviewer nálezy napsal textem a v okně by stálo „čisté review“. Povolení nástrojů se šablonou nemění, reviewer zůstává read-only — ta sada se skládá v kódu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Pod promptem, ne mezi sady skillů a ne na vlastní stránku (#389): text issue je
            // **materiál zadání**, tedy tatáž otázka jako prompt o řádek výš — co reviewer dostane,
            // než začne číst diff. Blokující kategorie pod tím mluví už o výsledku.
            Section {
                IssueTextToolField(tool: $settings.draft.global.issueTextTool)
            } header: {
                Text("Text issue z trackeru")
            } footer: {
                Text("Jméno není kontrakt, ale fakt o tomhle stroji: závisí na tom, jak si člověk MCP server pojmenoval, takže pevný seznam ani výchozí hodnota tady být nemůže — servery vypíše `claude mcp list`. Prázdné pole znamená **netahat**, ne „nezadáno“: session, která nemá co zavolat, stojí boot a nevrátí nic. U PR s odkazem na issue pak zůstane odznak `zadání není celé` s důvodem `nástroj není nastavený`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                StringListEditor(
                    items: $settings.draft.global.blockingCategories,
                    itemLabel: "Kategorie",
                    placeholder: "correctness",
                    addLabel: "Přidat kategorii"
                )
            } header: {
                Text("Blokující kategorie")
            } footer: {
                // Jeden literál, ne konkatenace: složený výraz spadne na `Text(String)`,
                // které markdown neumí — a `CONFIRMED` by se vykreslilo se zpětnými
                // apostrofy místo monospace.
                Text("Nález blokuje, když je `CONFIRMED` a jeho kategorie je v téhle sadě. Na velikosti písmen nezáleží.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Brief na domově (#516) — **brána, ne předvolba**, a ze stejného důvodu jako agent nad ní:
    /// `Při prvním tiku dne` pouští session **bez kliknutí**.
    ///
    /// **Tři volby, ne přepínač.** Rozhodují se tu dvě věci — jestli se brief skládá vůbec a jestli
    /// ho smí spustit aplikace sama — a přepínač by je slil do jedné.
    ///
    /// **Globálně, bez override na repo**: brief mluví o celé desce, tedy o všech repozitářích
    /// naráz, takže hodnota na repo by neměla co znamenat.
    private var brief: some View {
        Section {
            Picker("Brief na domově", selection: $settings.draft.global.brief) {
                ForEach(BriefMode.allCases, id: \.self) { mode in
                    Text(verbatim: mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Brief na domově")
        } footer: {
            Text("Výchozí stav je **vypnuto** a blok se pak na domově nekreslí vůbec. Když se zapne, složí až tři věty — co přibylo, co hoří a co si vzít první — session Claude Code **bez jediného nástroje**: dostane hotový stav aplikace (pruhy desky, počty, dění) a jenom ho přeformuluje. Nečte repozitář, nesahá na disk ani na GitHub. `Na požádání` čeká na tlačítko, `Při prvním tiku dne` k tomu složí brief jednou denně, jakmile je fronta načtená.\n\n**Jeden brief stojí kolem 0,09 $** (změřeno; drtivou většinu z toho spolkne start session, ne délka shrnutí). Při `Při prvním tiku dne` je to zhruba **2,50 $ měsíčně**. Cena každého běhu je na řádku pod briefem a počítá se do `Dneska stálo`; do denního limitu automatických běhů se **nezapočítává**.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Návrh review (#520) — **brána, ne předvolba**.
    ///
    /// Leží mezi agentem a briefem, protože je to tatáž otázka jako u agenta („co aplikace udělá,
    /// aniž bych na to klikl“), jen o mém rozdělaném review místo o souborech v kopii repa.
    ///
    /// **Text musí říct, kde ta hranice končí**, jako u odesílání a u agenta: předvyplní se to,
    /// co pak odesílám — a odesílání se tím nemění, pořád je za potvrzením s celým payloadem.
    private var autoDraft: some View {
        Section {
            Toggle("Složit návrh review po doběhnutí reviewerů", isOn: $settings.draft.global.autoDraft)
        } header: {
            Text("Návrh review")
        } footer: {
            Text("Výchozí stav je **vypnuto**. Když se zapne, převezme aplikace po doběhnutí **všech** reviewerů do rozdělaného review nálezy, u kterých si je reviewer jistý (`CONFIRMED`) a nikdo mu neodporuje. Ostatní zůstanou **sporné** — u nálezu je vidět značka i důvod a převzít je jde kliknutím. Odmítnutý nález se nepřevezme nikdy. **Nic se tím neodesílá**: review odchází pořád jedině z potvrzení, ve kterém je celý payload, a verdikt zůstává návrhem. Návrh se dá zahodit jedním tlačítkem a panel je pak prázdný jako bez téhle volby. Repo si to může přebít.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Agent na vlastním PR (#510) — **brána, ne předvolba**.
    ///
    /// Leží hned pod režimem review, protože je to tatáž otázka („co aplikace pustí, aniž bych na
    /// to klikl“), jen o druhé session. Vlastní stránka by znamenala jeden knoflík na stránku
    /// a schovala by ho zrovna vedle toho, s čím se má číst.
    ///
    /// **Text je tu důležitější než přepínač**, jako u odesílání: je to jediné místo, kde se
    /// zapíná session, která **mění soubory** — a musí být jasné, kde ta hranice končí (v kopii
    /// repa; push zůstává na potvrzení).
    private var agent: some View {
        Section {
            Toggle("Pustit agenta po cizím review", isOn: $settings.draft.global.autoAgent)
        } header: {
            Text("Agent na vlastním PR")
        } footer: {
            Text("Výchozí stav je **vypnuto**. Když se zapne, pustí se na **vlastním** PR po cizí aktivitě (review Copilota, komentář kolegy) session, která upraví soubory v kopii repa — nikdy v tvém klonu, nikdy na cizím PR a nikdy po tvém vlastním komentáři. Commit dělá aplikace a **do remote se nesáhne**: force push zůstává na potvrzení, jako doteď. Běhy čerpají tentýž denní limit jako automatické review. Repo si to může přebít.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
