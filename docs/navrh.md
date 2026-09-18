# Vizuální návrh (mockup)

Jak se pracuje s mockupem: kde je, čím se čte, jak se aktualizuje a co znamená „zapracovat
do návrhu“. Pravidlo samotné — **co se musí nakreslit a odsouhlasit dřív, než na to vznikne
issue** — je v [`CLAUDE.md`](../CLAUDE.md), sekce *Návrh (mockup)*.

## Kde návrh je

**Zdroj je [`docs/navrh.html`](navrh.html) v repu.** Publikovaná kopie, na kterou se posílá
odkaz, žije jako artifact `PRism — návrh vizuální revize`:
<https://claude.ai/code/artifact/5206622c-19b2-4c4e-9041-849d5b6d4a51>. Obojí musí odejít
**v jednom commitu a jednom publikování** — rozejít se smí leda na dobu jedné úpravy.

**A rozešlo se to** (zjištěno u #500): publikovaná kopie neměla sekci 39, kterou #152 do repa
přidalo — commit tedy proběhl a publikování ne. Poznat to jde jedině **porovnáním**, protože
artifact nemá diff a v repu na tom nic vidět není. Postup je krátký: `action: "read"` uloží
publikovanou verzi do souboru, z něj se odřízne obálka (`<body>` … `</body>`, kterou přidává
publikování) a zbytek se pustí přes `diff` proti `docs/navrh.html`. **Jednosměrný diff je
v pořádku** — repo napřed —, kdežto řádek, který má jedině publikovaná kopie, znamená, že
někdo editoval artifact a ne repo. Zvedat to na hlídané pravidlo nemá cenu: ta kontrola
proběhne stejně při každém publikování, protože nástroj bez přečtení živé verze publikovat
odmítne.

**K tomu porovnání patří grep na duplicitní kotvy.** Dvě sekce s týmž `id` se v repu slijí, aniž
by to git nahlásil, a `#sNN` pak vede vždycky na tu první; vzniká to v dávce, kde si dvě větve
vezmou totéž „další volné číslo“ (co tomu předchází, je
v [`paralelni-vyvoj.md`](paralelni-vyvoj.md#číslo-sekce-v-mockupu-přiděluje-orchestrátor)).
**Musí vyjít prázdný:**

```bash
grep -o 'id="s[0-9]*"' docs/navrh.html | sort | uniq -d
```

**A publikovanou kopii je levnější porovnat než přečíst.** Soubor, který `action: "read"` uloží,
je celý návrh i s obálkou — u #501 **15 847 řádků** —, takže čtení do kontextu je nejdražší
způsob, jak se dozvědět, že na adrese nic cizího není. `diff` odpoví na tutéž otázku bajt na bajt
a je to tvrzení o **celém** souboru, ne o tom, čeho si kdo všiml: #501 tím zjistilo, že na adrese
nic cizího neleží, #533 že kopie „souhlasí znak po znaku“. Proti souboru **z `mainu`** se
porovnává tehdy, když je otázka „leží na adrese něco, co v repu není“ — vlastní nemergnutá sekce
se v tom diffu ukáže legitimně a je to ta jediná odchylka, která tam smí být.

Je to jedna HTML stránka: tokeny v `:root` a pod nimi **59** sekcí (poslední přišla se #523 —
druhé kolo nad mými komentáři, **číslo 60**; před ní přidalo #516 brief na domově s **číslem
58**, #513 sérii PR ve frontě s **číslem 57**, #511 běžícího agenta v sekci `Větev`
s **číslem 56** a #510 agenta na vlastním PR s **číslem 55**
— číslo sekce a jejich počet spolu nesouvisí, protože čísla se v dávce přidělují dopředu, takže
u #523 stojí devětapadesát sekcí pod nejvyšším číslem 60: `s59` si vzal soused ze stejné dávky).
To číslo patří ke
každému zákresu, který sekci přidává, a **čte se grepem, ne po paměti** — do #442/#443 tu
stálo 28, kdežto sekcí bylo 30, u #500 tu stálo 38 nad devětatřiceti (sekci 39 přidalo
#152, aniž by to číslo zvedlo), u #515 tu stálo 45 nad šestačtyřiceti, protože sekci 46
přidalo #517 a číslo nezvedlo (nález Copilota), a u **#526 tu stálo 48 nad devětačtyřiceti**
— sekce 49 přišla s #529 a číslo zůstalo zase stát. **Sekci 47 přidalo #506** (itinerář review)
a číslo zvedlo v témže commitu — stejně jako **sekci 54** u #528, **sekci 53** u #512,
**sekci 55** u #510, **sekci 56** u #511, **sekci 57** u #513, **sekci 58** u #516
a **sekci 60** u #523
— o číslo se u dávky nehádá,
přiděluje ho orchestrátor
(#537), takže tenhle údaj patří tomu, kdo sekci kreslí:

```bash
grep -c '<section class="section" id="s' docs/navrh.html
```

**V rozdělané dávce může být ten počet menší než nejvyšší `id`, a je to v pořádku, ne
rozejití:** #530 kreslilo `s51` nad padesáti sekcemi, protože čísla v dávce přiděluje
orchestrátor dopředu a `s50` si vzal soused (#526), jehož PR se slil až potom. Mezera se slitím
zavřela, ale **další volné číslo se z tohohle počtu nedopočítává** — v dávce ho dostaneš
v zadání (viz *Jak se aktualizuje*), mimo dávku se čte z nejvyššího `id`:

```bash
grep -o 'id="s[0-9]*"' docs/navrh.html | sed 's/[^0-9]//g' | sort -n | tail -1
```

Většina sekcí kreslí jednu obrazovku nebo jeden stav v rámu okna (`.win`) a vedle sebe má
poznámky (`.notes`), proč je to tak; zbytek rozhodnutí vysvětluje — *Dvanáct stavů, které se
nesmí slít*, *Kde jsem si vybral, a co to stálo*, *Co by se muselo přepsat*.

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

Totéž platilo o **dashboardu**: 01 kreslila ten první (jedna karta `Ve frontě` a jeden blok
fronty), 21 ten se dvěma frontami podle #331. Obě jsou na stránce *Přehled* pod sebou —
a od #515 jsou obě záznamem toho, co v okně **není**, viz odstavec o zrušených obrazovkách níž. Stejné páry jsou **02 a 24** a **19 a 25** (#390): 02 a 19 kreslí dnešní obrazovky,
24 přidává labely a vyžádané reviewery do pravého panelu a 25 ten panel do tabu *Commity*.
Od zakreslení nového labelu z nabídky stojí vedle **24** ještě **26**, a je to tentýž vztah, jen
o krok dál: 24 se mergnutím #392 stala záznamem dneška (nabídka labelů v panelu v okně opravdu
je), takže se do ní zakládání nekreslí — 26 kreslí **jen dvě obrazovky nabídky a jednu větu
v panelu**, ne celý panel znovu. Ve stejném vztahu stojí **38 k 04**: 04 je záznam dnešní
*Konverzace* i s composerem, 38 kreslí **jen ten composer s nabídkou emotikonů**, protože se
nemění nic jiného. A **37 vedle 36** je jiný případ — nejsou to dvě podoby jedné obrazovky, ale
dvě akce v téže sekci panelu (*Větev*), takže spolu leží na stránce *Panel u vlastního PR* a ani
jedna z nich zatím není záznamem dneška. A **41 vedle 02** je zase případ jako 24: kreslí
**jediný výřez hlavičky** s pilulkou `mimo zdroje` a dva stavy záložky, o které se ví jen adresa
(#531) — celá hlavička ani celé okno se nepřekresluje. Tentýž vztah má **42** (mapa PR, #501):
kreslí zvětšený pás s legendou a k tomu jeden výřez „jak to leží v okně“, ne celé okno znovu.
A **49 vedle 10** je totéž ještě o krok dál (#529): 10 je záznam dnešního okna nastavení se sedmi
stránkami, 49 kreslí **jen tu osmou** (*Systém*) a k tomu dlaždici Docku — a ta je jediná věc
v celém dokumentu, která **není v okně**, takže se na ni nedal vzít žádný existující kus.

**Výřez nemusí ležet na stránce té sekce, kterou nepřekresluje** (#527). Sekce **44** kreslí pruh
záložek před ukončením a po startu, tedy tentýž pruh jako **02** — a leží přesto na stránce
*Start a poruchy*, ne u ní. Rozhoduje **kdy tu obrazovku vidíš**: puntík načítání je vidět pár
sekund po spuštění a nikdy potom, takže patří k ostatním startovním stavům, kdežto 02 je klidný
stav téhož okna. Je to tentýž rozdíl jako u sekcí, do kterých se z obrazovky jen přijde (viz níž),
jen se místo *odkud se otevírá* ptá na *kdy nastane*.

**Sekce, do které se z obrazovky jen přijde, leží na stránce toho místa, odkud se otevírá.**
Sekce 20 kreslí surovou session na stránce *Průběh*, protože se otevírá z výpisu kroků; **28**
(sheet s celým logem a s hunkem) leží na stránce *Kontroly*, protože odtud vede
`Ukázat celý log` — i když tentýž sheet otevírá i diff v *Změněných souborech*. Když do jedné
obrazovky vedou dvě cesty, vybere se ta, kvůli které sekce vznikla, a druhá se v textu
pojmenuje; dvě kopie téhož sheetu na dvou stránkách by se rozešly.

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
U #501 se to promítlo hned do **sedmi rámů okna** (02, 03 dvakrát, 04, 19 dvakrát a 25): mapa PR
nahradila pilulku `+X −Y`, takže `.diffstat` ze všech odešel a pás přišel. Že se přitom
**nepřekreslily celé**, si nijak neodporuje — mění se jedna řádka chromu, a ta se mění všude,
kde byla. Jediné místo, kde pilulka zůstala, je **záznam měření stupňů pruhu v sekci 19**
(`.stripbox`): to je záznam z #316, ne dnešní obrazovka, a přepsat naměřená čísla bez nového
měření by z nich udělalo odhad.
Poznávací znak to **není** „vedle ní nestojí novější varianta“: 01 má vedle sebe 21, 02 má
od #390 vedle sebe 24 a 19 má 25, a záznamem dneška jsou pořád dál — mít vedle sebe kresbu
budoucího stavu neznamená, že se ta dnešní přestane udržovat. Zapsat to jako „vědomě
zastaralé“ nestačí: zápis ve specifikaci nikdo nečte s obrázkem v ruce, a u #299 se
takových zápisů sešlo pět.

**Když nová sekce tu starou obrazovku zruší, přebírá po ní i roli záznamu dneška** (#515).
Sekce **45** (deska podle mého tahu) nekreslí variantu domova vedle karet — karty
a oba bloky front **odešly**, takže dashboard v sekcích **01** a **21** už v okně nikdo
nenajde. Překreslit je nejde (obrazovka, kterou kreslily, neexistuje) a smazat je taky ne:
bez nich se nedá přečíst, proti čemu #515 vzniklo, a #181 s #331 se na ně odkazují. Vyřešilo se
to **jednou větou navrch v jejich hlavičce** — *tohle odešlo s #515, dnešní Přehled je sekce
45* — a zbytek obou sekcí platí dál (rail, hlavička okna, stavový řádek, rozřazení podle
autora). Je to třetí případ vedle „novější se do starší nepřekresluje“ a „záznam dneška se
překreslit musí“: **zrušená obrazovka se označí, ne přepíše.**

**Totéž platí o tokenech**, jen tam to nikdo neuvidí očima: `--mint` ve světlé větvi se u #309
v aplikaci ztmavil kvůli kontrastu (`#0E8F80` → `#0C7E71`) a v mockupu zůstala stará hodnota, tedy
přesně to, čemu má pravidlo „tokeny jsou `Palette` jedna ku jedné“ zabránit. Barva se mění
**v obou** světlých větvích (`:root` i `:root[data-theme="light"]`), jako se u #277 měnily obě
tmavé.

**A jedna sekce může mít víc obrazovek.** Sekce 09 jich má od #531 **tři** — dnešní hledání,
vložený odkaz a dvě úrovně nad repem —, protože všechny tři jsou tatáž karta ⌘K a odpovídají na
sebe navazující otázky. Sekce 20 jich má dvě — živý výpis kroků a surovou
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
nenašla **ani jeden**, ta níž všechny. Falešně pozitivní nález u osmi vybraných jmen nehrozí
natolik, aby se za tuhle šířku platilo — a kdyby přišel, je to pobídka se podívat, ne šum.

```bash
for c in lchip chip-add rv-list rv-row rv-av nl-bar nl-add nl-step fd-to; do
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
   **další volné číslo** (ne to, kam v UI patří) — **v dávce ho ale nepočítáš, dostaneš ho
   v zadání** (viz níž) — a zařadí se do stránky podle místa v aplikaci;
   mapa stránek je v kostře dokumentu, v komentáři nad rozcestníkem.
2. Publikovat: `Artifact` s `file_path: "docs/navrh.html"`,
   `url: "https://claude.ai/code/artifact/5206622c-…"` a `favicon: "🎨"`. Titulek a favicon
   zůstávají — mění se obsah, ne identita stránky; hodnoty jsou výš, v *Kde návrh je*.
3. **Commitnout ten soubor toutéž změnou.** Publikovaná kopie bez commitu znamená, že v repu
   je jiný návrh než na odkazu, který jsem dostal.

**Publikuje se celý dokument, takže dvě session nad týmž artifactem se přepisují** (#410).
Publikování není merge: nahraje se celý obsah stránky a to předchozí z ní beze slova zmizí.
Plynou z toho tři věci.

**Kdo publikuje z branche, vtáhne do ní napřed `main`** — jinak odkaz zahodí všechno, co se
mezitím mergnulo, a vypadá to, že se ta práce nestala.

**Pozdější publikování smete to dřívější, i když ta dřívější změna pořád leží v PR.** U #410 to
tak dopadlo: zákres sekce *Dění* se publikoval ve 20:25, o půl hodiny později publikoval jiný
agent ze **své** branche (přejmenování v sekci 20, #327) a v rozcestníku pak bylo pod *Oknem
aplikace* jen *Přehled*. Uživatel tedy neměl co odsouhlasit, a ta sekce přitom celou dobu ležela
v repu — publikovaná kopie o ní jen nevěděla.

**Po každém publikování z branche si odkaz otevři a zkontroluj, že tam ta sekce je.** A když leží
víc zákresů naráz, rozhoduje **pořadí publikování**: naposled má jít ten, který se má ukazovat.
Naplánovat to ale jde jedině tam, kde ty větve drží jeden člověk — **v dávce to nikdo
nenaplánuje** (#537), protože pořadí mergů se předem neurčuje a kdo je dřív hotov, jde dřív.
Místo plánu se proto publikuje **znovu po každém mergi, ze slitého stavu**: každé další
publikování jde ze stavu, který obsahuje i to předchozí, takže poslední merge srovná i to, co
smetl ten před ním — a nikdo nemusí vědět, že je poslední. Postup je
v [`paralelni-vyvoj.md`](paralelni-vyvoj.md#číslo-sekce-v-mockupu-přiděluje-orchestrátor).

**Mimo dávku se číslo sekce kontroluje proti `mainu` v den publikování**, ne proti stavu při
zakládání branche (#410). „Další volné číslo“ z bodu 1 si dvě nezávisle vzniklé branche vezmou
obě: #401 i #410 vyšly z mainu, na kterém bylo 25 sekcí, takže si obě vzaly **26** — a po
mergnutí obou by
dokument měl kotvu `#s26` dvakrát. Přečísluje se ta, která se merguje později (u #410 na **27**),
a s číslem se mění i eyebrow sekce a komentáře u jejího CSS. Že je kotva navěky (viz *Kde návrh
je*) tomu neodporuje: nemergnutá sekce ještě žádnou kotvu, na kterou se odkazuje, nemá.

**V dávce se číslo nekontroluje, ale přiděluje** — dostaneš ho v zadání od orchestrátora (#537),
takže tahle kontrola tam pro tebe není práce. Dvě větve vzniklé v jedné vlně se totiž proti
`mainu` porovnají obě správně a obě dostanou tutéž odpověď: po #410 se to tak stalo znovu u #500
a #531, které si vzaly `s40` obě. Kontrola proti mainu chytá větev, která leží týden; souběh
v jedné vlně nechytá vůbec. Podrobně v
[`paralelni-vyvoj.md`](paralelni-vyvoj.md#číslo-sekce-v-mockupu-přiděluje-orchestrátor).

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

### Proč brána sedí u zakládání issue, ne až u prvního commitu

Je to schválně, ne z opatrnosti: **issue je zadání, ne nápad.** Od chvíle, kdy je na GitHubu,
popisuje cílový stav a podle něj se programuje — a subagent, který ho dostane do zadání, už
o návrhu nediskutuje. Kreslit mockup až po něm proto znamená **dohánět návrhem to, co už je
napsané slovy**, a slova o vzhledu nesou vždycky míň než obrázek: „přidej do panelu sekci
s větví“ se dá nakreslit desítkou způsobů a devět z nich se pak přepisuje.

Druhý důvod je cena. **Levná je změna vzhledu jedině dokud je to CSS v mockupu** — pak je to
SwiftUI, testy nad geometrií, screenshot k proklikání a případně další kolo revize. Brána
u zakládání issue je tedy jediné místo, kde ta oprava stojí minuty.

Proto je to taky **jediná schvalovací brána v tomhle repu** — výjimka z pravidla *Rozhodování*
v [`CLAUDE.md`](../CLAUDE.md), které jinak říká, že se návrhová rozhodnutí nepředkládají ke
schválení. Schvaluje se **obrázek**, ne návrh implementace.

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
