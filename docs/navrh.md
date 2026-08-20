# Vizuální návrh (mockup)

Jak se pracuje s mockupem: kde je, čím se čte, jak se aktualizuje a co znamená „zapracovat
do návrhu“. Pravidlo samotné — **co se musí nakreslit a odsouhlasit dřív, než na to vznikne
issue** — je v [`CLAUDE.md`](../CLAUDE.md), sekce *Návrh (mockup)*.

## Kde návrh je

**Zdroj je [`docs/navrh.html`](navrh.html) v repu.** Publikovaná kopie, na kterou se posílá
odkaz, žije jako artifact `PRism — návrh vizuální revize`:
<https://claude.ai/code/artifact/5206622c-19b2-4c4e-9041-849d5b6d4a51>. Obojí musí odejít
**v jednom commitu a jednom publikování** — rozejít se smí leda na dobu jedné úpravy.

Je to jedna HTML stránka: tokeny v `:root` a pod nimi 25 sekcí. Většina kreslí jednu
obrazovku nebo jeden stav v rámu okna (`.win`) a vedle sebe má poznámky (`.notes`), proč je to
tak; zbytek rozhodnutí vysvětluje — *Dvanáct stavů, které se nesmí slít*, *Kde jsem si vybral,
a co to stálo*, *Co by se muselo přepsat*.

**Čte se po stránkách, ne jako svitek** (#332). Rozcestník vlevo je poskládaný jako aplikace —
okno, sedm záložek pull requestu v pořadí z `PullRequestTab`, dialogy, poruchy, rozhodnutí —
a v jednu chvíli je vidět jedna stránka. Do srpna 2026 to byl jeden dokument o 400 kB, ve
kterém se hledalo scrollováním.

**Číslo sekce je kotva, ne cesta.** `id="sNN"` zůstávají navěky a `#s07` platí: router z odkazu
pozná stránku, otevře ji a doskočí na sekci (umí to i na kotvy uvnitř sekcí, jako `#s20raw`).
Odkazuje se na ně ze specifikace, z README, z `docs/testovani.md` i z issues, takže přečíslovat
je nejde. **V rozcestníku ale vypsaná nejsou**: číslo je pořadí vzniku, ne pořadí čtení, a
v liště by stálo `02, 03, 19, 04, …` — tedy přesně ten nepořádek, který stránkování schovává.
Vidět je na samotné sekci a ve výsledcích hledání, protože ta jsou na úrovni sekcí.

**Hledá se ⌘K** — přes celý text sekcí, bez ohledu na diakritiku, s výřezem okolo shody.

**Skrývání stránek zapíná až JavaScript.** Bez něj je dokument jeden svitek jako dřív, a to je
záměr: grep nad souborem i vyříznutí jedné sekce do samostatného souboru (viz *Jak se ověří*)
musí fungovat dál.

**Jedna obrazovka může mít víc sekcí — a pak leží na jedné stránce.** Sekce 20 (*Průběh · výpis
a surová session*) kreslí druhou vrstvu téhož tabu jako sekce 07 a stojí **vedle ní, ne místo
ní**: 07 je záznam toho, jak tab vypadá dneska, a ten je potřeba právě k porovnání — proto v ní
zůstávají i starší popisky fází (`klon`, `čte diff`), které se při implementaci zamítly. Když
tedy dvě sekce ukazují totéž jinak, poznává se návrh podle toho, že k němu je záznam rozhodnutí
ve [specifikaci](superpowers/specs/2026-07-31-prism-design.md).

Totéž platí o **dashboardu**: 01 kreslí ten dnešní (`DashboardView` má opravdu kartu `Ve frontě`
a jeden blok fronty), 21 ten se dvěma frontami podle #331. Obě jsou na stránce *Přehled* pod
sebou. Stejné páry jsou **02 a 24** a **19 a 25** (#390): 02 a 19 kreslí dnešní obrazovky,
24 přidává labely a vyžádané reviewery do pravého panelu a 25 ten panel do tabu *Commity*.
**Novější sekce se do té starší nepřekresluje** — záznam dneška je to jediné, proti čemu se dá
aplikace srovnat, takže bez něj by každé srovnání hlásilo rozdíl, který není chyba, dokud se to
issue neudělá. Platí to i tehdy, když nová sekce mění **jen kus** obrazovky: 24 nekreslí celé
okno, ale výřezy panelu (`.frame.flat` s `aside.side`), a i tak stojí vedle 02, ne v ní.

**U sekce, která je záznamem dneška, platí to obráceně: ta se překreslit musí** (#299). Když se
v aplikaci něco změní, mění se s tím i ta sekce — jinak v návrhu zbude obrazovka, kterou v okně
nikdo nenajde, a čtenář nemá jak poznat, jestli chybu má aplikace, nebo návrh. Takové sekce
poznáš podle toho, že **kreslí to, co okno umí dneska** — u #299 to byla sekce **02**
(dnešní `Přehled`; #215 z ní vzalo souhrn checků, #291 rozdělil hlavičku karty na dvě podoby),
**03** (patička nálezu po #283), **19** (seznam commitů po #316) a **01** (rail po #278).
Poznávací znak to **není** „vedle ní nestojí novější varianta“: 01 má vedle sebe 21, 02 má
od #390 vedle sebe 24 a 19 má 25, a záznamem dneška jsou pořád dál — mít vedle sebe kresbu
budoucího stavu neznamená, že se ta dnešní přestane udržovat. Zapsat to jako „vědomě
zastaralé“ nestačí: zápis ve specifikaci nikdo nečte s obrázkem v ruce, a u #299 se
takových zápisů sešlo pět.

**Totéž platí o tokenech**, jen tam to nikdo neuvidí očima: `--mint` ve světlé větvi se u #309
v aplikaci ztmavil kvůli kontrastu (`#0E8F80` → `#0C7E71`) a v mockupu zůstala stará hodnota, tedy
přesně to, čemu má pravidlo „tokeny jsou `Palette` jedna ku jedné“ zabránit. Barva se mění
**v obou** světlých větvích (`:root` i `:root[data-theme="light"]`), jako se u #277 měnily obě
tmavé.

**A jedna sekce může mít víc obrazovek.** Sekce 20 jich má dvě — živý výpis kroků a surovou
session —, protože **odpovídají na jinou otázku nad týmž místem** a druhá je východ z první.
Rozdělit je na dvě sekce by ten vztah zahodilo; dokud spolu obrazovky takhle souvisejí, patří
k sobě. Poznají se podle vlastního `<h3>` a vlastního bloku `.notes`.

**Soubor v repu je, a je to změna proti dřívějšku** (#332). Do té doby tu stálo, že v repu být
nemá — s odůvodněním, že návrh je živý dokument a z každé úpravy by byl commit, review a merge.
Otočilo se to ze dvou důvodů. Artifact drží verze, ale **nemá diff**: u 400 kB dokumentu se
„co se v návrhu změnilo“ nedá zjistit jinak než dívat se na obě verze vedle sebe. A návrh se
mění **spolu s kódem** — pravidlo o dokumentaci ve stejném commitu na něj sedí stejně jako na
`docs/*.md`, takže ten commit stejně vzniká. Cena je jeden velký soubor v diffu; platí se rád.

Adresa publikované kopie je zapsaná výš. Dohledat se dá i jinak: nástroj `Artifact` s
`action: "list"` vypíše artifacty uživatele i s adresami.

**Favicon publikované kopie je 🎨** a zapsaný je právě proto, aby se nehádal (#299). Publikování
si ho vynucuje jako povinný parametr a nikde jinde uložený není — v repu, v `Artifact`u ani ve
výpisu artifactů se přečíst nedá. U #277 se ho proto nepodařilo dohledat a agent zvolil 🎨 podle
svého; ikonka v tabu je ale to, podle čeho si člověk stránku hledá, takže **zůstává tahle**
a při každém publikování se předává znovu. Titulek `PRism — návrh vizuální revize` platí
stejně: mění se obsah, ne identita stránky.

## Jak se z něj čte

**Grepem nad `docs/navrh.html`.** Je to soubor v repu, takže se čte přímo — hodnota, podle které
se pak kreslí (poloměr, mezera, barva), se musí přečíst v CSS doslova, ne odhadnout z popisu.

```bash
grep -n "inline-find" -A 20 docs/navrh.html
```

**Soubor nemá `<!doctype>` ani `<html>`** — publikování si obal doplňuje samo a vlastní by se
zdvojil. Otevřený z disku proto běží v **quirks mode** (`document.compatMode === "BackCompat"`).
Změřeno u #332, že se to **na rozměrech neprojeví**: karta, rám okna, proužek řádku i sloupec
mikrografu vyšly v obou režimech na bod stejně. Kdyby na tom někdy něco stálo, obal se přidá při renderu
(viz *Jak se ověří*), ne do souboru.

**`WebFetch` je na publikovanou kopii, ne na zdroj** (a `curl` na ni nefunguje — artifacty jsou
soukromé a dostane skořápku aplikace nebo 403). Sahá se po něm jedině tehdy, když je potřeba
ověřit, **co je doopravdy publikované** — typicky když je podezření, že se soubor a artifact
rozešly.

**Tokeny v `:root` jsou `App/Views/Palette.swift`.** `--bg`, `--panel`, `--line`, `--ink`,
`--accent`, `--crit`, `--find` a spol. sedí na `Palette` jedna ku jedné včetně obou motivů
(`#F4F6FA`/`#080A0F` = `Palette.background`, `#5B47E0`/`#8B7CFF` = `Palette.accent`). Když se
mění barva, mění se **obojí** — jinak se paleta a návrh rozejdou a další srovnání bude tvrdit,
že chybu má aplikace.

**Token, který `:root` nedefinuje, v návrhu potichu nedělá nic** (#384). Nedefinovaná custom
property není v CSS chyba — deklarace se stane neplatnou při výpočtu hodnoty a vlastnost spadne
na `unset`, takže v souboru vypadá zákres hotově a na obrazovce po něm není ani stopa. U hover
patky bloku (`.block > .more-rows`) stálo `var(--hover)`, token toho jména paleta nemá, a hover
tedy nekreslil **nic**: `getComputedStyle` hlásil `background-color: rgba(0, 0, 0, 0)` v obou
tématech. Vyšlo to najevo až u #371, při implementaci, tedy o tři verze návrhu později.

Nový token se proto **nevymýšlí** — paleta je zdroj a tokeny jsou s ní jedna ku jedné, takže
token bez protějšku v `Palette` je token, podle kterého se nedá nic naprogramovat. Sáhne se po
tom, který ten odstín už drží (tady `--panel-3` = `Palette.raised`); doopravdy nová barva
znamená napřed pole v `Palette`. Grep, který **musí vyjít prázdný** — vypíše každé použití
`var(--…)`, které `:root` nedefinuje:

```bash
grep -o 'var(--[a-zA-Z0-9-]*' docs/navrh.html | sed 's/var(//' | sort -u > /tmp/used.txt
grep -oE '(^|[{; ])--[a-zA-Z0-9-]+[[:space:]]*:' docs/navrh.html |
    grep -o '\-\-[a-zA-Z0-9-]*' | sort -u > /tmp/defined.txt
comm -23 /tmp/used.txt /tmp/defined.txt
```

Obráceně je to jen uklízení, ne vada (`comm -13` vypíše tokeny, na které se nikdo neodkazuje).
Za pozornost stojí i **čtvrtý blok**: barvy a stíny jsou v `:root`, v `@media
(prefers-color-scheme: dark)` a v obou `:root[data-theme=…]`, takže token, který v jednom
z nich chybí, se v tom tématu tiše obarví z toho světlého `:root` — ověřeno u #384, že se v těch
třech přebíjecích blocích neliší nic než čtyři tokeny bez motivu (`--ui`, `--mono`, `--radius`,
`--radius-sm`).

**Třída, kterou si někdo bere jako vnořenou, se naholo definovat nesmí** (#390). Je to opačná past
než mrtvý token a stejně tichá: pravidlo zabere, jenže **jinde, než na co se kouká**. `.lbl` je
v dokumentu ve třech komponentách vnořený popisek (`.runbar .lbl`, `.findnav .lbl`, `.set-row .lbl`)
a rozhoduje u něj jen barva a velikost písma; první zákres labelů PR ho přesto napsal naholo
(`.lbl { border: 1px solid …; border-radius: 20px; background: var(--panel-3) }`) a **podstrčil ho
všem třem**. Změřeno `getComputedStyle`em nad dokumentem: `border: 1px solid`, `border-radius: 20px`
a vyvýšený podklad tam, kde návrh chce prostý text — na `main` u všech tří `0px none`. Spravilo to
nové jméno (`.lchip`), ne specificita.

Kontroluje se to **u jmen, která zákres přidává**, ne plošným výpisem: plošný hlásí i jména,
která se takhle míjejí odjakživa a jsou v pořádku (`.acts` proti `.frow .acts`, `.subtabs` proti
`.stripcut .subtabs`), takže z něj zbyde seznam k odklikání. Grep níž **musí vyjít prázdný**
a ověřený je z obou stran — nad zákresem s vrácenou regresí hlásí.

**Vzor nesmí být zakotvený na začátek řádku a na jednu třídu v rodiči.** První podoba téhle
kontroly byla `^\.[a-z][a-z0-9-]* +\.$c`, a ta **mlčí u většiny skutečných tvarů**: rodič
s víc třídami (`.card.go .goto`, `.card.alarm .big`, `.frow.crit .bar` — všechny tři v tomhle
souboru opravdu jsou), potomkový kombinátor (`.runbar > .lchip`), dvě úrovně (`.a .b .lchip`)
i odsazené pravidlo. Ověřeno vložením regrese ve všech čtyřech tvarech: zakotvená podoba
nenašla **ani jeden**, ta níž všechny. Falešně pozitivní nález u pěti vybraných jmen nehrozí
natolik, aby se za tuhle šířku platilo — a kdyby přišel, je to pobídka se podívat, ne šum.

```bash
for c in lchip chip-add rv-list rv-row rv-av; do
    grep -qE "[a-z0-9)]([ ]*[>+~][ ]*|[ ]+)\.$c([^a-z0-9-]|$)" docs/navrh.html &&
        echo "POZOR: .$c je jinde vnořený"
done
```

Rozměry z CSS se berou jako body 1 : 1 (`font-size: 11.5px` → `.font(.system(size: 11.5))`,
`border-radius: 6px` → `cornerRadius: 6`). Není to samozřejmost, je to zvyklost tohohle repa —
dodržuje ji dnešní kód a odchylka od ní musí být zapsaná jako rozhodnutí.

## Jak se aktualizuje

Upravit `docs/navrh.html` a publikovat nástrojem `Artifact` **s `url` té existující stránky**.
Bez `url` vznikne druhý artifact — a dva návrhy jsou horší než žádný, protože se nedá poznat,
který platí.

1. Upravit sekci, které se to týká — novou obrazovku přidat jako další sekci **i s poznámkami**
   (`.notes`), protože návrh bez důvodů se za měsíc nedá obhájit ani změnit. Nová sekce dostane
   **další volné číslo** (ne to, kam v UI patří) a zařadí se do stránky podle místa v aplikaci;
   mapa stránek je v kostře dokumentu, v komentáři nad rozcestníkem.
2. Publikovat: `Artifact` s `file_path: "docs/navrh.html"`,
   `url: "https://claude.ai/code/artifact/5206622c-…"` a `favicon: "🎨"`. Titulek a favicon
   zůstávají — mění se obsah, ne identita stránky; hodnoty jsou výš, v *Kde návrh je*.
3. **Commitnout ten soubor toutéž změnou.** Publikovaná kopie bez commitu znamená, že v repu
   je jiný návrh než na odkazu, který jsem dostal.

Nové obrazovky se kreslí **stejnými třídami jako zbytek** (`.win`, `.card`, `.pill`, `.mini`, …).
Vlastní styl pro jednu sekci znamená, že se návrh přestal skládat z jednoho systému, a to je
přesně to, čemu má mockup bránit. Totéž platí o kostře dokumentu (`.doc-*`) — ta je oddělená
schválně, aby se navigace nemíchala do toho, co sekce kreslí.

## Co znamená „zapracovat do návrhu“

Změna vzhledu se do mockupu překreslí **dřív, než na ni vznikne issue na GitHubu**, a schvaluje ji
uživatel (pravidlo je v [`CLAUDE.md`](../CLAUDE.md)). Pořadí kroků:

1. Najít sekci, které se to týká, a **překreslit ji** — ne přilepit vedle druhou verzi.
2. Do poznámek u sekce napsat, **co se změnilo a proč** — jednou větou, stejným tónem jako zbytek.
3. Publikovat na tutéž adresu a **poslat odkaz uživateli**.
4. Počkat na souhlas. Teprve pak `gh issue create` — a v textu issue odkázat na tu sekci návrhu,
   protože od té chvíle je cílový stav nakreslený a nemusí se popisovat slovy.

Co pod pravidlo **nespadá**: srovnávat aplikaci s tím, co v mockupu už nakreslené je. Tam se
návrh nemění, takže není co schvalovat ani co překreslovat — issue se založí rovnou (#283).

Když se při implementaci ukáže, že to nakreslené nejde nebo je horší, platí obvyklé pravidlo
z `CLAUDE.md` (*Rozhodování*): rozhodni, **zapiš do specifikace co se změnilo a proč** a napiš to
do popisu PR. Odchylka od návrhu, která je v záznamu rozhodnutí, je v pořádku — potichu jiná
obrazovka není.

## Jak se ověří, že to sedí

Stejně jako dřív: **obrázek vedle obrázku**, ne čtení kódu. Sekce se vyřízne z `docs/navrh.html`
do samostatného souboru (i s `<style>`) a vyrenderuje headless Chromem; postup i s příkazem je
v [`docs/testovani.md`](testovani.md), sekce o kontrole vzhledu.

**Stav na `:hover` se fotí přepsaným selektorem, ne přepsanou deklarací** (#384). Headless snímek
nemá myš, takže se ve **výřezu** (ne ve zdroji) přepíše `:hover` na třídu a ta se přidá jednomu
prvku — `.block > .more-rows:hover` → `.block > .more-rows.hoverprobe`. Deklarace tím zůstává ta
z návrhu, takže se testuje pravidlo ze souboru; přepsat rovnou barvu znamená vyfotit vlastní
domněnku. Přepis patří do skriptu, který výřez skládá, a s `assert` na počet zásahů — když se
selektor v návrhu přejmenuje, má sonda spadnout, ne vyfotit nedotčený stav.

Barvu je u toho lepší **odečíst, ne odhadnout z obrázku**: `--dump-dom` po `getComputedStyle`
vrátí přesné `rgb()`, a **`rgba(0, 0, 0, 0)` je právě ta odpověď, kterou dává neplatná
deklarace** — tedy i mrtvý token. U #384 to rozhodlo: `rgba(0, 0, 0, 0)` před opravou proti
`rgb(28, 33, 44)` = `#1C212C` = `--panel-3` po ní, v obou tématech.

**Vyříznout se musí, i když je dokument stránkovaný** — a ne kvůli délce stránky, ale kvůli
`--screenshot`: ten bere viewport **od horní hrany dokumentu**, takže po odrolování na sekci
vrací prázdný obrázek. Změřeno u #332: sonda v tomtéž běhu hlásila sekci správně 18 bodů pod
horní hranou okna, a snímek přesto vyšel jednobarevný. Není to vada dokumentu a nemá cenu to
opravovat v něm.

U #181 to našlo čtyři odchylky, které kontrolou kódu prošly — pevnou šířku sloupce místo poměru
`1.45fr 1fr`, chybějící popisky v hlavičkách bloků, chybějící blok `Co teď` a odsazený proužek
řádku. U #216 to našlo uzel osy o 16 bodech místo 24. Zpaměti se to nepozná.

**A na jednu vadu vyříznutá sekce nestačí: celý dokument se musí vyrendrovat taky** (#299).
Fragment, který zůstane **mimo `.doc-page`** — typicky zbytek po přeskládání stránek —, router
nikdy neskryje, takže se kreslí **na každé stránce**. U #332 takhle v dokumentu zbyla osiřelá
patička nálezu se čtyřmi tlačítky a visela pod rozcestníkem i pod každou obrazovkou; ve výřezu
jedné sekce ji přitom nebylo jak vidět. Stačí jeden snímek titulní stránky s dost vysokým
`--window-size` a `--virtual-time-budget=3000` (router zapíná až JavaScript):

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
    --hide-scrollbars --window-size=1400,1400 --virtual-time-budget=3000 \
    --screenshot=doc.png "file://$PWD/docs/navrh.html"
```

Grep to nechytá: `<footer>` s tlačítky je platné HTML a v souboru vypadá jako kus sekce.
