# PRism

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Veškerá analýza
žije ve skillech Claude Code; aplikace rozhoduje, kdy spustit který skill a kde, odchytí
strukturovaný výstup a vykreslí ho.

Hranol rozloží jeden paprsek na spektrum. Tahle aplikace dělá totéž s pull requestem —
pustí na něj několik nezávislých reviewerů a jejich nálezy schválně neslévá do jednoho
názoru.

> **Na GitHub vede jediná cesta a otevírá ji jen člověk.** Aplikace umí odeslat review,
> odpovědět do vlákna a napsat komentář pod PR, ale výhradně přes jeden modul a jen na výslovný
> pokyn — review navíc proti commitu, který jsi opravdu viděl. Nic se neodesílá samo — ani
> návrh verdiktu, ani reviewer.
>
> **A jedině tam, kde se to povolilo.** Odesílání je ve výchozím stavu vypnuté — zapíná se
> v nastavení, globálně nebo u jednoho repa. Dokud si o to někdo výslovně neřekne, neodejde
> nikam nic.

## Stav

**Aplikace dělá to, kvůli čemu vznikla: pustí review na moje skutečné PR a ukáže nálezy.**

Okno má **vlastní hlavičku se záložkami** (#180): vlevo semafor, vedle něj domácí záložka
`Přehled` a otevřená review, vpravo novinky, obnovení a nastavení. Seznam PR není trvalý sloupec —
je obsahem domácí záložky, takže diff dostane celou šířku okna. Otevřené review zůstává otevřené
a tečka u záložky nese jeho stav; u běžícího se točí prstýnek, u rozdělaného je pero. **Zavření
záložky nic nezahodí.**

**Pruhem se přepíná `⌃Tab` a `⌃⇧Tab`** (#245) — dokola a **včetně domácí záložky**, protože se na
ni chodí nejčastěji (je za ní fronta) a bez ní by zkratka nad jediným otevřeným PR nedělala nic.
Pořadí je pořadí pruhu, ne pořadí použití. Funguje to i **s kurzorem v rozepsaném review**:
změřeno, že se do textu nevloží tabulátor ani nepřeskočí fokus — key equivalent tlačítka se
vyhodnocuje dřív, než se klávesa dostane k textovému editoru. Zkratky stojí v nápovědě u domácí
záložky, protože jinak by po nich v okně nebyla žádná stopa.

Barvy si okno drží samo (`Palette`), včetně fialového akcentu — systémová šedá je neutrální,
kdežto tenhle návrh stojí na neutrálech posunutých do modrofialové. **Od #277 z ní jdou i barvy
diffu**: pozadí přidaného a odebraného řádku byla do té doby systémová zelená a červená s krytím,
takže se v tmavém režimu mísila směrem k černé a blok změny vypadal jako tmavý obdélník. Teď jsou to
vyčíslené hodnoty a řádky se v tmavém režimu odlišují o třetinu víc (ΔE 16,0 → 21,8), aniž by se
zhoršila čitelnost obarveného kódu.

Obsahem domácí záložky je **dashboard** (#181), ne prázdné „Vyber pull request“. Odpovídá na tři
otázky, na které se do té doby muselo hledat po okně: **kolik toho čeká**, **co z toho blokuje**
a **co mám rozdělané** — plus co mě dneska stálo review, i s grafem za posledních sedm dní. Pod
kartami je fronta seřazená **podle závažnosti**, ne podle času, vedle ní rozpad nálezů podle
revieweera za týden a blok `Co teď` s akcemi: pustit review na všechno, co neběželo (ptá se na
potvrzení — je to jediné kliknutí v aplikaci, které utratí víc než jednu session), nebo se vrátit
k nejstaršímu rozdělanému review. Nic se pro to nedotahuje; všechna ta čísla už v aplikaci byla,
jen roztroušená.

V pravém horním koutu stojí, kdy se seznam naposledy načetl a **kolik zbývá do příštího dotazu** —
`poslední tik 09:41 · za 43s znovu` (#237). Poslední tik je hodina, protože je to bod
v minulosti; příští je odpočet, protože otázka u něj zní „jak dlouho ještě“ — a při rate limitu,
kde čekání roste až na patnáct minut, je to celý obsah té informace. Delší čekání se píše ve dvou
jednotkách (`za 12min 29s znovu`). Zatímco se aplikace ptá, je tam místo čísla `ptám se…`.

**Mezera mezi číslem a jednotkou tam schválně není** (#260) — je to vědomá odchylka od české
typografie, kterou si aplikace platí vlastním formátováním odpočtu, protože systémový formát
mezeru v české locale má a nejde z něj vyndat.

Napravo v hlavičce stojí **`⌘K`** — command palette (#184), jedno pole nad nálezy, soubory
otevřeného PR, pull requesty a akcemi. Popsaná je níž.

Po startu si ověří, že má `gh`, `git` i `claude` a že je `gh` přihlášený — jinak řekne, co
chybí a čím se to spraví. Pak se otevře seznam pull requestů napříč repozitáři, který se
sám obnovuje. **Řádek začíná titulkem** (#172) a souřadnice — `repo #číslo · autor · čas
poslední změny` — stojí pod ním: seznam míchá repozitáře, ale otázka „co to je“ přijde dřív než
„odkud to je“. Stav review nese **barevná hrana řádku**, takže se fronta dá přejet očima, a vedle
odznaku je **proužek s podílem reviewerů** — z něj je poznat, jestli nálezy hlásí jeden reviewer,
nebo se na nich shodli dva. Blokující nález má vlastní barvu i text (`3 nálezy · 1 blokuje`); do
#172 se nedal od tří kosmetických odlišit vůbec. Při
výpadku sítě zůstanou poslední známá data a nad seznamem se objeví pruh, že nejsou
aktuální; při rate limitu pruh říká, kdy to zkusí znovu.

**Seznam se dá zúžit filtrem** (#117) — ikona v toolbaru vlevo, odškrtávají se v ní repozitáře
a autoři (uvnitř osy „nebo“, mezi osami „a“: dvě repa znamenají obojí, repo + autor jeho PR v tom
repu). U každé položky je **počet PR, kterých se týká** (#199), takže je před kliknutím vidět, co
se za ní schová; počítá se z **plného** seznamu, takže se odškrtáváním nemění — jinak by číslo
říkalo něco o pohledu místo o tom, co zapnutí položky udělá. Že je filtr zapnutý a kolik schovává,
je vidět na ikoně **bez otevírání nabídky**, protože skrytý filtr je způsob, jak přijít o review;
a když schová všechno, řekne to a nabídne se vypnout — zelené „Žádné PR k review“ by nad zapnutým
filtrem tvrdilo opak pravdy.

Filtr je **pohled, ne seznam**: nic se tím nepřestane stahovat, nezahodí se diffy ani rozdělaná
review, běžící review běží dál, automat plánuje dál a okno nastavení pořád vidí i schované repo.
**Nepřežije restart** — je to jediné, co umí PR schovat úplně, a zmizelý PR vypadá jako vyřízený.
Na trvalé schování jsou **zdroje** v nastavení (search dotaz umí i `-author:`), což je změna toho, co
se stahuje.

U vybraného PR je tlačítko **Spustit review**. Za ním se stane tohle: dotáhne se head
commit, připraví se odpojený pracovní strom a v něm se spustí headless session Claude Code
omezená na čtení. Řádek mezitím ukazuje `ve frontě · clone` → `běží 0/1` → `čisté` nebo
`N nálezů`; běh jde kdykoli zrušit. Nálezy se uloží na disk, takže přežijí restart, a v panelu
vedle diffu je seznam nálezů po kategoriích, s odznakem u těch blokujících. **Návrh verdiktu**
(`approve` / `request changes` / *není z čeho soudit*) se z nich předvyplní v tabu `Moje review`
a je u něj napsané, že je to návrh; do #218 stál navíc v hlavičce, kde byl druhou kopií téhož.
Kliknutím na nález diff odskočí na jeho `file:line`.

Nad záložkami je **hlavička ve třech řádcích** (#174, přesázená podle návrhu u #218). Nahoře
titulek a vedle něj číslo PR, vpravo `Spustit review` — a je to **jediné akcentové místo v celé
hlavičce**. Pod tím souřadnice: stav PR jako plná kapsle s puntíkem, `autor chce sloučit
větev → base`, `owner/repo`, souhrn kontrol a odkaz na GitHub. Větve se do okna dostaly až
s #174 a je to první věc, kterou u cizího PR hledám. Třetí řádek je **pruh běhu**: kapsle
reviewerů (`● php-review 2`, klik filtruje jejich nálezy) a za nimi — když review běží — dráha
průběhu s popiskem `test-coverage · 2 z 3 hotovo · 1:12`.

Když se **hlava PR rozejde se sha, proti které platí nálezy**, přibude pod tím řádek s oběma —
dokud se rovnají, je to trivia, jakmile se rozejdou, je to nejdůležitější údaj na obrazovce,
protože všechno pod ním mluví o kódu, který na větvi už není. Vpravo u záložek je rozsah změny
(`+X −Y`) a za ním pět čtverečků v poměru přidaného a odebraného.

**Stav pracovní kopie je ve stavovém řádku dole** (`Pracovní kopie připravená · HEAD 4f2ac91`),
ne v hlavičce: je to stav prostředí, ne údaj o pull requestu. Selhaný checkout je výjimka —
zůstává bannerem v hlavičce, protože se u něj musí vypsat celý výstup `gitu` a z něj se teprve
pozná, co dělat dál.

Detail PR má **pět záložek** (#183, dvě přidal #242): `Přehled` říká, jak to teď stojí (popis,
fakta, co se změnilo od minule), `Změněné soubory` je diff a `Konverzace` je **časová osa toho,
co se dělo** — s uzly,
u kterých tvar nese druh, se seskupenými commity (jedenáct pushů nesmí utopit dva komentáře),
filtrem `Vše / Komentáře / Vlákna / Události` a značkou `Nové od tvé poslední návštěvy`. U force-pushe
je rovnou u události napsané, že tím zastaraly nálezy, a tlačítko pustit review znovu.

Za nimi stojí `Nálezy` (tabulka všeho, co reviewery nahlásily) a `Průběh` (co dělaly) — a mezi
`Konverzací` a `Nálezy` je **dělič**: nalevo je to, co je na PR a co má i GitHub, napravo to, co
s ním udělaly naše reviewery.

V `Průběhu` má dráhu **každý reviewer z nastavené sady**, ne jen ten, který už na tomhle PR běžel:
otázka je „kde je které z mých review“ a *ještě nezačalo* je taky odpověď. Tři různá „nic tu není“
mají proto tři různá slova — `nespuštěno` (v sadě, tady nic), `ve frontě` (review běží a tenhle čeká
na slot) a `bez průběhu` (běh v záznamu je, ale jeho osa ne, což jsou soubory z doby, kdy se ještě
neukládala). Dráha po skillu, který v nastavení už není, **nezmizí** — nesla by s sebou doběhlé
review — jen je označená `mimo sadu`.

Záložky jsou podtržené jako na GitHubu a **odznak má každá** (#218), jen počítá pokaždé něco
jiného: `Přehled` novinky od poslední návštěvy, `Změněné soubory` počet souborů, `Konverzace`
kolik je toho k přečtení, `Nálezy` kolik jich je (**červeně, když něco blokuje**) a `Průběh`
**puntík, ne počet** — „běží“ je stav, ne množství. Volba se pamatuje **u každého PR zvlášť**
a otevírá se `Přehled` — popis a diskuze se čtou dřív než kód, kterého se týkají.

Pod dlaždicemi je blok **`Kontroly na GitHubu`** (#209): kolik checků prošlo, kolik běží a kolik
spadlo, a pod tím řádek na každý s dobou běhu. **Nejhorší stav vyhrává** — dvanáct zelených
a jeden červený je červený stav — a **přeskočený check není prošlý**; přeskočené se sbalí za
číslo, protože jich na monorepu bývá většina. U spadlého je odkaz na log; ten se do aplikace
nestahuje.

Pod popisem PR jsou **dlaždice s fakty** (#198): kolik je commitů a kolik z nich přibylo od minule,
kolik souborů se mění a v kolika je nález, hlava PR a — **jen když se rozešla** — sha, proti které
platí nálezy. Nic se pro ně netahá z API; jsou to čísla, která v okně už byla, jen roztroušená.
Dlaždice, o které se nedá nic říct, se nekreslí.

Úplně nahoře v `Přehledu` je **co se změnilo od tvé poslední návštěvy** (#173): nové commity,
cizí review, komentáře — a hlavně **přepsaná historie větve**, protože právě po ní zastarají
nálezy i rozdělané review. Tenhle jeden případ má vlastní barvu i větu o důsledku a nabízí
pustit review znovu; jinak je to tiché oznámení. Banner se ukáže, **jen když opravdu něco
přibylo**, a u PR otevřeného poprvé nikdy — „od tvé poslední návštěvy" by tam znamenalo „od
začátku věků". Značka se posune hned při zobrazení, ale to, co je vidět, se během běhu aplikace
nemění — odskok do `Změněných souborů` a zpátky o něj nepřipraví. **Odchod na jiný PR a návrat
už je nová návštěva**, takže se banner podruhé neukazuje; projetí seznamu šipkami ho ale
nespotřebuje, protože se posouvá jen u PR, u kterého se stihla načíst konverzace. Odklidit ho jde
i rovnou křížkem vpravo.

**`Konverzace`** nese to, co se neváže k žádnému řádku: review ostatních s odznakem (`schválil`,
`vyžádal změny`), komentáře pod PR a vlákna, jejichž řádek v aktuálním diffu není (typicky
zastaralá po novém commitu). Ta se
kreslí **tou samou bublinou jako u kódu**, jen s cestou a řádkem nad ní — a **pod tím kus kódu,
ke kterému se komentář váže**, obarvený a naformátovaný jako v diffu. Kód se bere ze snímku,
který si GitHub k komentáři drží (`diffHunk`), takže platí pro commit, na kterém komentář vznikl
— nedopočítává se z dnešního souboru, kde už na tom řádku bývá něco jiného. Hunky bývají dlouhé
(medián 190 řádků), takže je vidět jeho konec po komentovaný řádek a **zkrácení je označené**.
Moje komentáře mají odznak `já`, text jde označit a zkopírovat (kromě úryvku kódu, kde selekci
brání gesto na výběr rozsahu) a konverzaci lze obnovit tlačítkem, aniž by se čekalo na tik
pollingu.

Mezi tím je vidět i **co se na PR stalo**: pushnuté commity (titulek a zkrácený sha),
vyžádaná a odebraná review, force push s `před → po`, převedení z draftu, merge, zavření
a změna base — každé s avatarem toho, kdo za tím stojí, a s relativním časem. Události jsou
jednořádkové, ne karty jako komentáře, takže se přehled čte jako časová osa na GitHubu.
Bere se to **týmž dotazem** jako konverzace, takže to nestojí ani jedno kolo po síti navíc.
Zavření hned po mergi se nekreslí zvlášť (mergnutím se PR zavírá), zavření bez mergnutí ano.

**Texty se renderují jako Markdown** — nadpisy, seznamy včetně zaškrtávacích, bloky kódu,
citace, odkazy. Vlastní blokový parser bez závislosti (jako obarvení kódu): systémový umí
formátování uvnitř řádku dobře, ale bloky tiše spolkne. Zvládá i **HTML, které do komentářů
posílají boti** — `<!-- … -->` se nekreslí (jako na GitHubu), `<details>` je rozbalovátko
a odkazy zůstávají klikatelné. Tabulky zůstávají jako monospace řádky a kód v blocích se
neobarvuje: jazyk z fence je volný řetězec, takže mapovat ho na obarvovací pravidla znamená
hádat, a špatně obarvený cizí kód je horší než neobarvený.

**`Změněné soubory`** ukazují **diff v plné šířce**: soubory pod sebou s hlavičkou, která při scrollu
zůstává nahoře, souhrn `N souborů · +X −Y` a menu na skok mezi soubory. Přejmenování, nové,
smazané i binární soubory jsou označené; dlouhé řádky se zalamují, protože 120 znaků se do
plné šířky vejde. **Zalomí se až tam, kde kód nemá kam pokračovat** (#236) — sloupce s čísly ubírají
místo jen vlevo. Do té doby se zalamovalo o jejich šířku dřív, takže se při šířce obsahu 600 pt vešlo
41 znaků místo 57 a u pravého okraje zůstávalo mrtvé místo; při té samé chybě se navíc bublina nálezu
kreslila přes poslední řádky bloku. Počty `+X` a `−Y` jsou obarvené jako znak změny v samotném řádku — zeleně
a červeně, v řadě záložek PR i v hlavičkách souborů, takže „velký přírůstek“ a „velké mazání“
jsou poznat na první pohled.

**Hlavička souboru nese celou cestu** (#219) — složka tlumeně, jméno tučně (`src/Vault/`**`SecretClient.php`**).
Do té doby tam bylo jen jméno, takže u dvou souborů, které se jmenují stejně, nešlo poznat, který
je který. V úzkém sloupci ustupuje složka, ne jméno.

**Lišta nad diffem** má vlevo pohled a procházení nálezů, vpravo `Rozbalit vše`. Co se používá
jednou za čas (bubliny nálezů u řádků, `Zobrazit jen diff`), sedí v nabídce pod ním. Přepínače
postranních sloupců v ní **nejsou**: strom i panel se skládají u sebe, takže by to byly třetí
dveře k témuž — zkratky `⌘1` a `⌘2` platí dál a stojí v nápovědě u těch tlačítek.

Diff se dá kreslit **dvěma způsoby** a přepíná se segmentovaným přepínačem v liště nad ním:
`Pod sebou` je klasický unified diff (odebrané a přidané řádky pod sebou, dvě čísla vlevo),
`Vedle sebe` staví starý obsah vlevo a nový vpravo, spárovaný po řádcích. U přepsaného bloku
se tím odpadá páření `-` a `+` řádků očima, což je u review nejčastější otázka. Blok
odebraných řádků se s následujícím blokem přidaných spáruje pozičně; přebytek na kterékoli
straně dostane prázdnou buňku s neutrálním pozadím. Kontextový řádek stojí na obou stranách,
hlavička hunku, rozbalovací řádek, bubliny i poznámky `git`u jdou přes celou šířku. Všechno,
co diff umí pod sebou, umí i vedle sebe — bubliny, rozbalování kontextu, obarvení, sbalování
souborů i skok z tabulky nálezů. **Komentovat jde i rozsah řádků**: **táhni myší přes sloupec s čísly** (nebo z pilulky s ikonkou) —
vybraný rozsah se průběžně zvýrazňuje a po puštění se otevře komentář. Tažením **přes kód** se od
#157 vybírá text, takže rozsah se táhne vlevo od něj. Bublina visí u posledního řádku rozsahu,
jako na GitHubu. Rozepsaný komentář jde ještě roztáhnout **⇧ klikem** na `+` u jiného řádku (to
tažení neumí, protože komentář už existuje). Rozsah smí přeskočit i mezeru mezi hunky a odesílá se
jako `start_line`/`start_side`, tedy tak, jak to čeká GitHub.

**Rozepsaný komentář visí jen v té půlce, které se týká** —
komentář k odebranému řádku vlevo, k novému vpravo, a když komentuješ obě strany téhož řádku,
stojí oba **vedle sebe**. Nálezy a cizí vlákna zůstávají přes celou šířku, protože se na stranu
nevážou a nesou delší text.

**S jakým pohledem se diff otevírá, je v nastavení** (`Diff → Pohled na diff`, v souboru
`global.diffLayout`); výchozí je `Pod sebou`, tedy dosavadní chování. Přepínač v liště je
proti tomu jen odchylka: platí napříč pull requesty do zavření aplikace a do konfigurace
nezapisuje — nastavení říká „takhle to chci mít“, přepínač „teď se na to podívám jinak“.
Per repo se pohled nenastavuje, protože jak se čte diff, je vlastnost člověka, ne repozitáře.

**Klik na hlavičku souboru jeho diff sbalí a rozbalí**, jako na GitHubu — u PR přes deset
souborů je to hlavní způsob, jak se v něm pohybovat. Hlavička zůstává vidět i se `+N −M`
a s kapslí, kolik je v souboru nálezů (červenou, když je mezi nimi blokující). V horní
liště je `Sbalit vše` / `Rozbalit vše` a skok na soubor nebo na nález sbalený soubor sám
otevře.

V mezerách mezi hunky jsou **šipky na rozbalení kontextu** — dotáhnou kód, který v diffu
není, po dvaceti řádcích nebo celý úsek naráz. Obsah souboru se čte z GitHubu až na
kliknutí; když se mezera rozbalí celá, hunky se slijí a hlavička mezi nimi zmizí.
`Zobrazit jen diff` sbalí všechno zpátky. **Kód kolem nálezu, jehož řádek v diffu není,
se dotáhne sám** — nález bez svého kódu se nedá posoudit. Skok kamkoli v diffu je **stromem souborů** vlevo.
`Zobrazit jen diff` se schovalo do nabídky u `Rozbalit vše` (#219).

**Kód se vybírá myší jako v editoru** (#157) — tažením přes libovolně mnoho řádků, ⌘C. Vybírá se jen
obsah, ne čísla řádků a ne znak změny, takže se do schránky nepřiplete diff. Kód proto kreslí
`NSTextView`, ne SwiftUI text: ve SwiftUI je každý text vlastní selekce, takže by šlo vybrat jen
jeden řádek. Souvislé řádky se slévají do bloku, který končí u hlavičky hunku, rozbalovacího řádku
nebo bubliny — vybírat jde přes celý úsek kódu mezi nimi, u většiny řádků přes celý hunk. Výběr
zůstává modrý, i když myš odjede jinam, a v pohledu vedle sebe žije **jen v jednom sloupci**.

Na to, co blok neumí — vybrat **přes** bubliny — je v kontextovém menu `Vybrat text z hunku…`: otevře
hunk v samostatném okně jako jeden text, s obarvením a s tlačítkem na zkopírování všeho. Zavírá se
Escem.

Na víc řádků je **pravé kliknutí**: `Kopírovat řádek`, u řádku, který leží v rozsahu tvého
rozdělaného komentáře, i `Kopírovat rozsah` s počtem řádků, a na hlavičce hunku `Kopírovat hunk`.
Ve schránce je **kód, ne diff** — bez `+`/`-`, bez čísel řádků a bez hlavičky hunku. U rozsahu přes
odebrané i přidané řádky se kopíruje **nová** verze; rozsah čistě na levé straně naopak ten starý
kód. Kopírováním **nevzniká komentář**, takže po sobě není co uklízet.

Tažení rozsahu pro komentář se s vybíráním textu snese: nad kódem dostane tažení výběr textu, nad
čísly a pilulkou výběr rozsahu. Pilulka s ikonkou má vlastní sloupec **vlevo od čísel**, takže už
žádné číslo nepřekrývá, a **táhnout jde i z ní**. Kurzor se mění po sloupcích: ruka nad pilulkou,
šipka nad čísly, textový nad kódem.

**V pohledu vedle sebe se dlouhý řádek nezalamuje, ale posouvá vodorovně** — jinak by jeden sloupec
narostl o zalomený řádek, druhý ne, a přestalo by platit, že vlevo a vpravo je tentýž řádek.

Kód je **obarvený podle jazyka** — vlastní pravidla, žádná externí závislost, paleta
Darcula v tmavém režimu a IntelliJ Light ve světlém. Barví se řádek po řádku bez paměti,
protože diff je útržek: víceřádkový komentář se obarví jen tam, kde začíná. Soubor
v neznámém jazyce zůstane jednobarevný.

**U přepsaného řádku svítí jen ta část, která se změnila** (#153) — sytější pruh přes zelené
nebo červené pozadí řádku, v obou pohledech. Do té doby svítil celý řádek, takže se u dlouhého
kódu rozdíl hledal přečtením obou verzí. Porovnává se **po slovech**, ne po znacích (přepsané
jméno svítí celé, ne po písmenech, a `==` proti `!=` je jedna změna), a jen tam, kde jsou si
řádky dost podobné: dvojice, která je ve skutečnosti smazání a přidání vedle sebe, zůstane
obarvená celá jako dosud. Obarvení syntaxe zůstává pod tím — word-diff je pozadí, syntaxe
barva písma. **Od #277 je ta vrstva o kus tišší**, protože v tmavém režimu pod sebou zhasínala
právě ten kód, kvůli kterému se člověk kouká: kontrast řetězce na ní byl 1,27, teď je 1,97.

**Prázdná strana dvojice je v pohledu vedle sebe prošrafovaná** (#277) — tam, kde je kód jen na
jedné straně, druhá polovina není prázdná plocha, ale díra se šrafou. Do té doby vypadala stejně
jako nezměněný řádek, takže z okna nešlo poznat, jestli se řádek nezměnil, nebo tam vůbec není.
Odlišuje se **texturou, ne světlostí**: v tmavém režimu už není kam ztmavovat a světlejší plocha by
křičela hlasitěji než sama změna.

**Nálezy visí jako bubliny u řádků, kterých se týkají** — pill kategorie, verdict, jméno
revieweru a rozbalitelný scénář selhání; blokující nález má červený pruh. Shodu dvou
reviewerů na jednom místě označí `2×`, ale jejich texty se neslučují. Nález na řádek, který
v diffu není, se neztratí: visí u hlavičky souboru a nabídne ten řádek dotáhnout. Bubliny
jdou vypnout v nabídce u `Rozbalit vše` (`Nálezy u řádků`) — vlákna konverzace zůstanou.

**Blokující nález je rozbalený rovnou, ostatní jsou značka na hraně řádku** (#185). Značka je
pruh s odznaky, kategorií, reviewerem a náhledem textu — kliknutím se rozbalí celá bublina
i s akcemi, druhým kliknutím se zavře. Rozbalit všechny by z diffu udělalo seznam nálezů
proložený kódem; sbalit i ten blokující je zase kliknutí navíc právě u toho jednoho, kvůli
kterému se PR nemerguje. **Odmítnutý se nerozbaluje nikdy** — je to jeden řádek s důvodem
a `Vrátit`, takže rozbalovat u něj není co. Skok z panelu i šipkami z lišty sbalenou bublinu
**rozbalí**, jinak by cíl skoku byl pruh, na kterém není co přečíst. Rozbalení se pamatuje
per PR, dokud PR nezmizí ze seznamu.

**Nálezy se procházejí šipkami v liště nad diffem** (#187): `2 z 3 nálezů` a dvě šipky, klávesově
`⌥↓` a `⌥↑`, na další blokující `⌥⇧↓`. Do té doby vedla cesta k dalšímu nálezu vždycky přes
panel — najít ho v seznamu a kliknout — takže seznam musel být pořád vidět. Zúžení
`jen blokující` mění, kam šipky skáčou; **odmítnuté nálezy se přeskakují**, protože nález,
kterému nevěřím, není práce k projití. Puntík zezelená, teprve až jsi prošel **všechna** místa,
ne když skončíš na posledním; a nálezy bez místa v kódu se do počtu neplete — nedá se na ně
skočit, tak je nápověda počítá zvlášť, aby `3/3` netvrdilo hotovo nad PR, kde zbývají v panelu.

**Ty zkratky do #151 fungovaly jen do prvního skoku** a stálo to za jednu poučku: SwiftUI páruje
u šipek zkratku **bez ohledu na shift**, takže `⌥↓` a `⌥⇧↓` jsou pro něj jedna klávesa a vyhrává
ta zaregistrovaná později. `⌥↓` tedy dělalo „další blokující“ — a protože blokující nález bývá
jeden, druhé zmáčknutí nikam neskočilo. Obojí je proto **jedno tlačítko** a shift se čte z události,
která akci spustila.

**Vlevo od diffu je strom souborů** (#197): cesty, u souboru s nálezem puntík (červený, když
blokuje). Skládá se na `⌘1` na proužek s počtem souborů, a týmž kliknutím se zase rozloží.
Popover `Přejít na soubor` odešel z lišty u #219 — byla to druhá dveře do téhož: sloupec je
na dosah jedním kliknutím a v liště bral místo, kvůli kterému se v užším okně nevešla.

**Napravo od diffu je panel se segmenty** (#182): nálezy jako karty a Moje review. Panel
je jediné místo, kde jsou vidět nálezy **bez místa v kódu** — chybějící testy nebo poznámky
k architektuře; kvůli nim samotné bubliny nestačí. Je vidět ve **všech** záložkách, protože nálezy
i rozdělané review patří k celému PR, ne k diffu. Klik kamkoli do karty odscrolluje diff
(a přepne na něj, když jsi v jiném tabu) tak, aby nad nálezem zůstalo pár řádků kontextu,
a bublinu na chvíli zvýrazní.

Segmenty jsou od #242 **dva**: `Průběh` se odstěhoval do vlastní záložky PR, protože se u kódu
nečte a u spadlé session se do 300 bodů nevešel ani důvod, ani konec logu. Nálezy v panelu
naopak zůstávají — tab `Nálezy` je druhý pohled na tu samou věc, ne přesun.

Do #182 byl panel **pod** diffem, kde si bral výšku — tedy to, čeho je u kódu nejmíň. Napravo bere
šířku, které je v okně přes celou obrazovku dost: v pohledu pod sebou zbude i na 14" displeji 126
znaků na stranu, takže slib „PHP na 120 znaků se vejde“ platí dál. **Složit ho jde na ⌘2** nebo
šipkou v jeho hlavičce; složený je proužek na hraně s počtem nálezů, který zčervená, když mezi
nimi něco blokuje. Šířka se táhne za levou hranu a pamatuje se.

**Nález je karta se závažností na hraně** (#175): červená blokuje, oranžová je běžný nález,
šedá odmítnutý — tatáž škála jako v řádku fronty, aby seznam a panel neříkaly o téže věci každý
něco jiného. Nahoře `blokuje · kategorie · reviewer`, pod tím shrnutí na tři řádky a dole místo
v kódu, ořezané **zepředu**, ať zůstane vidět jméno souboru a číslo řádku. Karta, na které stojí
procházení šipkami, má rámeček a popisek `tady jsi`, takže je z panelu i z lišty nad diffem
poznat totéž místo.

Do #175 to byla řaditelná tabulka. **V panelu se řazení podle sloupců nevrátilo**, a je to
vědomé: ve 300 bodech se sloupce nemají kam vejít — kategorie, místo a shrnutí se praly o místo
a odmítnutí muselo skončit jako odznak u kategorie. Platí tam pořadí podle závažnosti, tedy to,
v jakém se nálezy mají číst. **Tabulka se vrátila u #242, ale ve vlastní záložce** přes celou
šířku, kde je sloupců dost, viz níž.

### Záložka `Nálezy` (#242)

**Přes celou šířku se nález nasází jako tabulka**, což ve 300 bodech nešlo: na jeden řádek se vejde
závažnost, shrnutí, místo, `reviewer · kategorie` a akce. **Řadí se kliknutím na hlavičku sloupce**
— první kliknutí tak, jak se sloupec čte (závažnost od nejvážnějšího, text od „a“), druhé otočí.
Odmítnuté zůstávají naspod ať se klikne na cokoli: nálezu, kterému nevěřím, nemá konkurovat
platnému ani v cizím řazení.

**Řádek je místo, ne nález.** Když se dva reviewery potkají na jednom řádku kódu, je z toho jeden
řádek s odznakem `2×` — dva řádky by tvrdily, že jsou to dva různé nálezy. Souhrn nad tabulkou
proto počítá **nálezy** (`4 nálezy · 1 blokující · 3 místa`), a je to tentýž počet, jaký je na
odznaku záložky a jaký je v diffu v bublinách; počítá ho `Policy` na jednom místě.

**Kliknutí na shrnutí skáče do diffu** — přepne záložku a odscrolluje, tedy tentýž pohyb jako
odkaz na nález v `Přehledu`. Šipka na konci řádku ho **rozbalí**, a to do **té samé bubliny**,
jaká visí u kódu: celé texty, „Kdy to selže“, `Převzít do review` a odmítnutí u každého nálezu
zvlášť. Ve sbaleném řádku je odmítnutí v `⋯` — vědomý rozdíl proti bublině, kde jsou dva odkazy
vedle sebe: v tabulce by se šest odkazů opakovalo na každém řádku a přebily by shrnutí, kvůli
kterému se tabulka čte.

**Panel vpravo zůstává i tady**, protože smyčka nález → `Převzít` → text v mém review je ta hlavní
práce a musí se stát naráz. A **prázdná tabulka vysvětlí, proč je prázdná**: schované filtrem
reviewerů / reviewer nic nenahlásil / session spadla (i se `stderr`) — prázdná obrazovka se totiž
čte jako „čisto“, a schválený PR s neohlášenou chybou je ta nejdražší chyba, jakou tohle okno umí.

V **nejmenším okně odpadá sloupec `reviewer · kategorie`**: je to jediný, jehož obsah je i v bublině
u kódu a v chipech reviewerů nad diffem. Šířka se přitom **předává, ne vyjednává** (#220).

**Falešně pozitivní nález se dá odmítnout, aniž bys zahodil ostatní.** V bublině je
`Odmítnout: neplatný · irelevantní` — `neplatný` znamená „reviewer se mýlí“, `irelevantní`
„má pravdu, ale sem to nepatří“. Rozdíl stojí za dva knoflíky, protože první je vstup pro
doladění skillu nebo blokující sady a druhý ne; volný text u toho není, protože se nikam
neodesílá a nikdo by ho nečetl. Totéž jde z **kontextového menu** v tabulce
(`Označit jako…` / `Vrátit mezi platné`).

Odmítnutý nález se **nepočítá do návrhu verdiktu ani do řádku seznamu** — jeden falešný nález
s `CONFIRMED` v blokující kategorii tak nedrží celý PR na `request changes`. **Nikam ale
nezmizí:** v bublině se sbalí na jeden řádek s odznakem důvodu a tlačítkem `Vrátit`,
v tabulce zůstane ztlumený naspod. Schovaný nález se nedá přečíst a nedá se odlišit od
neexistujícího — a když je to moje rozhodnutí, musím mít jak zkontrolovat, co jsem odmítl;
proto tu není ani přepínač „schovat odmítnuté“. Když jsi nálezy odmítl všechny, řádek
v seznamu ukáže `odmítnuto · N`, **ne `čisté`**: „reviewer nic nenašel“ je jiné tvrzení než
„našel a já to zamítl“. Návrh verdiktu to napíše taky (`1 odmítnutý nález se nepočítá`).

Označení platí **jen pro ten commit** — nálezy jsou klíčované head commitem, takže nález
falešný nad starým kódem nemusí být falešný nad novým. Přežije to restart i **opakované
review týmž skillem**, které jinak celý předchozí výsledek přepíše. Odmítnutí u jednoho
revieweera nesundá nález druhého; odznak `2×` proto spadne na `1×`. A komentář, který jsi
z nálezu už převzal do svého review, se odmítnutím **nevyjme** — je to tvoje próza, vyjímá
se v `Moje review` a bublina to u takového nálezu napíše.

V liště panelu je **koš**, kterým se uložené nálezy zahodí — hodí se, když se změnila sada
skillů a v záznamu leží nálezy od revieweera, který už neběží. Je to hrubší nástroj než
odmítnutí: maže celý záznam viditelného commitu, historie starších zůstává, a na repu
v automatickém režimu se review vzápětí pustí samo.

**Zavřít aplikaci během review se musí potvrdit.** Ukončení session zabije a nálezy, které
už reviewer nahlásil, se ztratí — z řádku pak vyjde `neběželo`, tedy totéž jako u PR, který
nikdo nekontroloval. Dialog nabídne `Zpět` (výchozí) a `Ukončit`; co doběhlo, zůstává
uložené. Pád aplikace ani zabití zvenčí takhle odchytit nejde, proto to `bin/run.sh` při
rebuildu neobchází a aplikaci ukončuje tou samou cestou jako ⌘Q.

Nad diffem jsou **chipy reviewerů**: u každého je vidět, co udělal (`3 nálezy`, `čisté`,
`běží`, `selhalo`, `nejisté`) a kliknutím se jeho nálezy schovají z bublin i z tabulky.
Vpravo je **návrh verdiktu** — je to doporučení, ne akce. Sám nic neodešle; odeslat review
umí jedině člověk, a jedinou cestou (viz úvod). Tentýž návrh **předvyplní verdikt** v tabu
`Moje review`, takže se u něj pozná, jestli hodnota je z nálezů, nebo moje.
Filtr návrhem nehýbe, aby se schováním revieweera nedal „vyrobit“ approve.

**Když ze tří reviewerů jeden spadne, jde pustit znovu jen on** — pravým tlačítkem na jeho chip.
Za výsledky ostatních, které už leží na disku, se tím neplatí podruhé; jejich nálezy i průběh
zůstávají. Dokud nad PR nějaké review běží, je ta položka zakázaná: je to jedna úloha na pull
request.

V záložce **Průběh** má každý reviewer **vlastní dráhu** (#242): fáze `čeká na slot` /
`session` / `prochází kód` / `hlásí nálezy` vedle sebe, takže „kdo je hotový, kdo běží a kdo
spadl“ je jeden pohled. Do #242 to byly karty pod sebou v panelu 300 bodů širokém, ze kterých se
to muselo sesbírat scrollováním.

**Fáze jsou z toho, co v ose doopravdy je.** Fáze za tou, kam se běh dostal, zůstává nedotčená
i u úspěšně doběhlého běhu: reviewer, který `ReportFindings` nezavolal, nálezy **nenahlásil**, a to
není totéž jako nula. Pod dráhou je věta o tom, co se právě děje (`Právě: Read src/Cart.php`) nebo
čím to skončilo — a ta rozlišuje tři různé konce: nahlásilo nálezy, nahlásilo prázdný seznam
(čisto), nenahlásilo nic.

**Spadlá session dostane důvod, `stderr` a dvě tlačítka** — `Pustit znovu` a `Zkopírovat příkaz`
(příkaz, jakým by se ten reviewer spustil teď, k vložení do terminálu). Do #242 se v panelu lišila
od proběhlé jen barvou odznaku, protože na důvod ani na konec logu nebylo místo — a `čisté`
a `spadlo` se slít nesmí.

Podrobný výpis toho, co reviewer spouštěl — který soubor čte, co hledá, jaký příkaz spustil —
je pod rozbalením každé dráhy. Skládá se nativně z eventů, ne přeposíláním textu, takže
aplikace nepotřebuje vestavěný terminál; když je potřeba se do session vrátit, zkopíruje
se `claude --resume <id>` jedním tlačítkem. Osa zůstane i po doběhnutí běhu — a od #203
**přežije i restart aplikace**: ukládá se k běhu, takže se k ní dá vrátit druhý den i s tím
`sessionID`. Delší běh nadělá stovky událostí, proto se drží posledních 300 a kolik se jich
nevešlo, je u rozbalení vidět; ořezává se **začátek**, protože se do osy kouká kvůli tomu, čím
to skončilo.

U doběhlého revieweera je v hlavičce **cena, trvání a počet kol** — `0,23 $ · 11,8 s · 3 kola`.
Bere se to z toho, co nahlásila sama session, takže **zabitý běh je nemá**: nula by tvrdila, že
byl zdarma. Součet za dnešek je ve stavovém řádku, viz níž.

Na spodku okna je **stavový řádek**: vlevo hlášky o stavu celé aplikace (rozbitá
konfigurace, pozastavený automat kvůli dennímu limitu, soubory, které se nepodařilo
přečíst), vpravo **útrata za dnešek**, kdy se naposledy něco ohlásilo, a puntík u GitHubu
a u Claude. Puntík odpovídá na otázku „je to na mojí
straně, nebo mají oni výpadek?“ ještě předtím, než se člověk začne prohrabávat chybou:

| Puntík | Význam |
|---|---|
| ○ šedá | zatím nezjištěno — po startu, dokud se něco nestane |
| ● zelená | žádný incident na komponentách, které používáme — a poslední skutečné volání prošlo, nebo ještě žádné neproběhlo (nápověda řekne které) |
| ● žlutá | provozovatel hlásí incident na komponentě, kterou používáme (i když volání procházejí) |
| ● červená | poslední skutečné volání selhalo — nebo je stroj bez sítě, což řekne nápověda |

Červenou určuje **skutečný provoz**, ne sonda: polling se ptá `gh` každou minutu a review
pouští `claude`, takže lepší signál se nedá koupit a nestojí nic navíc. Zelenou dá i samotná
čistá status page — šedá znamená „nevíme nic“ a tady něco víme; puntík Claude by jinak zůstal
šedý, dokud neproběhne první review. Žlutá jde
ze status pages provozovatelů ([GitHub](https://www.githubstatus.com),
[Claude](https://status.claude.com)) — sleduje se z nich jen to, co aplikace používá, takže
incident v `Actions` nebo `Packages` puntík nerozsvítí. Kontroluje se po deseti minutách,
podmíněným dotazem (druhý dotaz je `304` bez těla), po selhaném volání častěji a **na pozadí
vůbec** — aplikace, kterou nikdo nevidí, nemá komu svítit. Když se stav služby zjistit
nepovede, nic se nezablokuje: puntík se řídí voláními a nápověda po hoveru řekne, co se
nepovedlo a kdy se to zjišťovalo.

Chování se řídí souborem `config.json` v `~/Library/Application Support/PRism/`: zdroje
PR, sada skillů, blokující kategorie, výchozí režim review, interval pollingu, kolik
session smí běžet naráz, rozpočet cache a model. Repozitář si může přebít režim
(`manual`/`automatic`), jazyk nálezů, skilly i kategorie.

**Nálezy chodí česky**, protože okno je české — u firemního repa s mezinárodním týmem se
dá přepnout na angličtinu, globálně i jen pro to jedno repo. Překládají se **až po
doběhnutí review**, jednou krátkou session na celý běh; reviewer sám dostane pořád tentýž
anglický prompt. Je to schválně: instrukce v promptu by kvalitu review ovlivnit mohla,
překlad po něm nemůže. Originál zůstává uložený vedle překladu a když se překlad nepovede,
ukáže se prostě anglicky.

Sada skillů se dá navázat na **programovací jazyk**: při review se z obsahu repa pozná,
čím je psané (`composer.json` a `.php` → PHP, `go.mod` → Go), a odpovídající sada se
použije. Smysl je nepouštět PHP skilly na Go repu — každý skill je jedna session.
Repu se sada **zapíše, jen když se od globální liší** — jinak by v konfiguraci vznikl
override, o který nikdo nežádal, a pozdější změna globální sady by takové repo minula.
Odhad se opakuje při každém review, dokud si repo neřekne o vlastní sadu; ručně nastavená
sada má vždycky přednost a detekci navždycky umlčí. Mapa jazyk → skilly je ve výchozím
stavu prázdná, takže dokud se nevyplní, detekce na nic nesahá. Soubor se zakládá sám s dosavadními výchozími
hodnotami, načítá se při startu i při návratu do aplikace, a když je rozbitý, běží se na
defaultech a je to vidět.

Editovat ho jde ručně, nebo **oknem nastavení** (⌘, nebo ozubené kolo v toolbaru). Okno
má dvě záložky: globální hodnoty a per repo, kde se u každého repa z posledního seznamu PR
nastavuje režim a případný override skillů a kategorií. Ukládá se samo do téhož souboru,
pár set milisekund po posledním úhozu, a změna se projeví bez restartu. Rozbitý soubor
editor **nepřepíše** — místo formuláře ukáže chybu a nabídne soubor otevřít. Dokud je
nastavení vepředu, hlavní okno se lehce rozostří.

**Dokud je okno otevřené a PRism je vpředu, zůstává před hlavním oknem** — kliknutí do hlavního
okna ho nezaklopí. **Fokus tím ale přejde na hlavní okno**: titulek nastavení zešedne a klávesy
jdou jinam, dokud se do nastavení nekliká znovu nebo se nedá `⌘,`. Není to opomenutí — klíčové okno
je v macOS právě jedno a udržet ho ve dvou nejde; co se u toho měřilo (včetně toho, že utility panel
nepomůže ani vzhledem), je v [`docs/architektura.md`](docs/architektura.md). Nad *cizími* aplikacemi ale neplave: jak PRism přestane být vpředu, okno spadne
na normální hladinu a leží pod nimi jako každé jiné okno; po návratu do aplikace je zpátky vpředu
i s rozepsanou hodnotou v poli. Zavřené okno se nevrací. Do #243 to bylo obyčejné okno, takže se za
hlavním oknem schovalo celé (středí se v něm) a vypadalo to, že se zavřelo — přitom bylo pořád
otevřené a `⌘,` ho jen znovu vytáhlo dopředu.

Zavírá se křížkem, ⌘W i **Escem** (#151) — sem se chodí přepnout jednu věc a jít zpátky
k review, takže cesta ven má být pod rukou. Rozepsaná hodnota se přitom **doručí**: Escem se
zavírá jedním hmatem uprostřed psaní, kdy těch pár set milisekund do automatického uložení
nemuselo uběhnout.

**Stavový řádek sčítá frontu** (#155): `12 PR`, `3 blokující`, `2 review` — kolik PR čeká, kolik
z nich má blokující nález a kolik má rozdělané review. Odznak v řádku seznamu mluví za jeden PR, tenhle souhrn za celou frontu — a sčítá
ji **celou**, ne to, co je vidět po filtru reviewerů, protože filtr je pohled, ne obsah. Blokující se
počítají bez odmítnutých nálezů, stejně jako v řádku. Dokud se seznam nenačetl, souhrn se neukáže
vůbec: nula blokujících nad nenačtenými daty by vypadala jako čisto.

Pod tím vším je vlastní cache repozitářů: bare partial clone do
`~/Library/Application Support/PRism/`, přihlášení delegované na `gh`, odpojený
`git worktree` pro každé review a úklid, který po každém pollingu zahodí repa bez
otevřeného PR a při překročení rozpočtu (10 GB) i ta nejdéle nepoužitá. Platí u ní, že
**vlastních klonů na disku se aplikace nikdy nedotkne** — pracuje výhradně ve své cache.
Uložené nálezy jsou klíčované head commitem: nové commity je označí jako zastaralé
a záznamy PR, který ze seznamu zmizel, se po třiceti dnech uklidí.

**Rozsah v1 podle specifikace je hotový** — všech pět fází (viz [`docs/stav.md`](docs/stav.md)).
Co přijde po něm, je v milnících M6 až M8.

Z nich už je hotové čtení konverzace: **vlákna od kolegů visí jako bubliny u svých řádků**,
vedle nálezů. Vyřešená jsou sbalená na jeden pruh s odznakem `vyřešeno` (nemažou se — je to
historie), moje komentáře mají odznak `já` a z každého se dá odskočit na GitHub. Konverzace
se načte při výběru PR a drží se, dokud se nezmění `updatedAt`; pollingem se netahá, aby
z jednoho tiku nebylo N podprocesů.

**A dá se do nich odpovědět.** V rozbaleném vlákně je pole na odpověď a tlačítko `Odpovědět`,
vedle něj `Vyřešit` (u vyřešeného `Znovu otevřít`) — všechno funguje jak v diffu, tak
v `Konverzaci`. Odeslaná odpověď se ve vlákně objeví hned, bez čekání na další načtení, protože
ji GitHub v odpovědi celou vrací. **Odpověď se nepotvrzuje** dialogem jako review: je to jedna
věta v diskuzi, dá se smazat a potvrzování každé by z okna udělalo klikačku — tlačítko je
pojmenované, takže se to nestane omylem.

Dvě věci, které nejsou vidět, ale jsou v tom to podstatné: **když odeslání selže, rozepsaný
text zůstane** na místě a chyba pod polem řekne, co s ní jde udělat. A **prázdná odpověď se
neodešle** — GitHub ji totiž přijme, nic nevytvoří a vrátí úspěch, takže by okno hlásilo
odeslanou odpověď, která nikdy nevznikla. `Vyřešit` se navíc nabízí jen tam, kde na to GitHub
dává právo; jinde by tlačítko vždycky selhalo.

**A dá se napsat i pod PR.** Na spodní hraně tabu `Konverzace` je pole `Napsat do konverzace
pod PR…` a tlačítko `Odeslat komentář`. Je to poslední věc, kvůli které se u review přepínalo
do prohlížeče. **Není to review**: nenese verdikt, nepotvrzuje se dialogem a v panelu
`Moje review` se neobjeví — proto sedí pod osou konverzace, ne v panelu, kde by se s review
pletlo. Platí u něj totéž co u odpovědi: po selhání text zůstane, prázdný komentář se neodešle
a bez povolení v nastavení neodejde nic.

**Rozdělané review se skládá v okně** a přežije restart: tělo, verdikt a řádkové komentáře
leží v `drafts/` vedle uložených nálezů, mimo dosah úklidu cache. Nový commit ho nesmaže,
jen zablokuje odeslání — vlastní próza nezastarává tak rychle jako strojové nálezy.

**Po novém commitu se review přenese, ale ne tiše.** Tlačítko se u zastaralého draftu jmenuje
`Zkontrolovat a odeslat…` a okno začne kontrolou kotev: u každého komentáře je vidět, jestli
**sedí**, **posunul se na jiný řádek**, jestli **nevíme, co na tom řádku bylo** (komentář z doby
před touhle funkcí), nebo že se **řádek v novém diffu ztratil**. Rozhoduje text řádku, ne jeho
číslo — komentáře si proto ukládají snímek kódu, ke kterému se psaly, a změna odsazení kotvu
neztratí. U každého se dá vybrat, co s ním: nechat, přepsat do těla review s odkazem na kód, nebo
vyjmout; ztracený komentář míří do těla, protože smazat ručně psaný text musí být tvoje
rozhodnutí. Teprve po přenesení se ukáže payload a dá se odeslat.

Hlavní smyčka je **nález → komentář mými slovy**: v bublině nálezu je `Převzít do review`,
které z jeho textu udělá můj komentář u toho řádku — a ten se dá přepsat. Převzatý nález
nese odznak `v mém review`, takže se nedá vzít dvakrát; rozeznává se podle revieweera, aby
u shody `2×` nesvítil odznak i u toho druhého. Vlastní poznámku přidá tlačítko, které se
objeví po najetí na řádek diffu.

**Co GitHub jako řádkový komentář nepřijme, jde do těla review jako odkaz na kód** —
permalink na commit, který se vyrenderuje jako obarvený úryvek. Týká se to nálezů mimo diff
a řádků, které v diffu nejsou (rozbalený kontext). Tlačítko to říká dopředu, včetně důvodu,
a po kliknutí se panel přepne na tab, kam text spadl.

V tabu **Moje review** je tělo, seznam všech řádkových komentářů a výběr verdiktu, který je
**předvyplněný návrhem z nálezů**. Takový verdikt je jen **obtažený** a stojí u něj popisek
`návrh z nálezů`; vyplněné tlačítko se zaškrtnutím zůstává vyhrazené mé volbě, která návrh
vždycky přebije (a druhý klik ji zruší, takže se návrh vrátí). Když návrh není — review
neproběhlo, spadlo, nebo je jeho záznam zastaralý — zůstává verdikt nevybraný a odeslat se nedá:
schválit PR proto, že reviewer spadl, je nejdražší chyba, kterou tahle aplikace umí udělat.
**Na vlastním PR se návrh nenabídne** a panel řekne proč: GitHub tam přijme jedině `Jen komentář`.

Návrh se přitom **nikam neukládá**. Rozdělané review z otevření PR nevznikne — dokud se do něj
něco nenapíše, žádný draft není a ikona v řádku seznamu nesvítí. Předvyplněný verdikt tedy
zastoupí chybějící volbu u review, které už nějaký obsah má; u čistého PR bez poznámek se návrh
přijme za svůj jedním kliknutím a panel to říká větou.

Seznam komentářů je jediné úplné místo: komentář na řádku, který
z diffu zmizel, se nemá kde ukázat jako bublina, ale tady je i s možností ho vyjmout.
Prázdný komentář se neuloží a odeslání zablokuje, protože GitHub takový payload odmítne —
a odmítne s ním celé review.

Že je něco rozděláno, je vidět **v řádku seznamu i v detailu** (ikona pera). Draft psaný
proti staršímu commitu má v tabu **banner** a odeslat se nedá; text zůstává.

Na jeden řádek jde napsat i **víc komentářů** a odejdou spolu s review. Panel u toho ale řekne,
co z nich vznikne: **samostatná vlákna vedle sebe, ne odpověď** pod prvním komentářem. Jinak to
GitHub neumí — v payloadu review se nedá říct „tenhle je odpověď na tamten“ a neodeslané vlákno
ještě nemá identitu, na kterou by šlo odkázat. Odpovědět jde na vlákno, které z odeslaného
komentáře vznikne.

### Command palette ⌘K (#184)

**Jedno pole na všechno.** S pěti PR a sedmi soubory je klikání únosné, s dvaceti už ne —
a paleta je zároveň jediné místo, kde se nemusí pamatovat, kde co v okně bydlí. Otevírá se
**⌘K** (druhé zmáčknutí zavře) nebo kapslí `⌘K` v hlavičce okna; ta tam je proto, že jinak by
o paletě věděl jen ten, kdo si přečetl release notes.

Výsledky jsou ve **čtyřech skupinách a jejich pořadí je pevné**: **Nálezy**, soubory otevřeného
PR, pull requesty, akce. Nálezy jsou první schválně — je to jediná věc, kterou tahle aplikace má
a prohlížeč ne, takže pořadí skupin je tvrzení o tom, k čemu je okno. Z každé skupiny je vidět
**nejvýš šest** řádků; strop je na skupinu, protože jinak by dvacet nálezů vytlačilo všechno
ostatní.

**Pole má fokus hned po ⌘K** a je **prázdné** — paleta je „začínám hledat“, ne „vracím se
k rozdělané práci“, takže po zavření z ní nezůstane text z minula.

**Prázdný dotaz není prázdné okno** — ukáže začátek každé skupiny, tedy nabídku toho, co je po
ruce: nálezy od nejvážnějšího, soubory v pořadí diffu, PR od naposledy změněného, akce v pevném
pořadí. Hledá se **bez ohledu na velikost písmen a diakritiku** (`nalez` najde `nález`) a víc slov
znamená **a zároveň** — `vault secret` najde nález ve `vaultu`, i když ta slova v textu vedle sebe
nestojí. Shoda v titulku váží víc než v podtitulku, začátek slova víc než vnitřek; nalezený úsek
je v řádku **zvýrazněný** — a to v tom textu, ve kterém se doopravdy potkal.

Hledá se i **podle autora a podle repozitáře**: autor u pull requestů, repo u pull requestů
i u nálezů. Obojí je proto vidět v podtitulku řádku (`connection#21663 · sykora-ji`) — výsledek,
u kterého není poznat, proč vyšel, vypadá jako chyba hledání. Soubory podle repa nejdou: jsou
všechny z jednoho otevřeného PR, takže by se vytáhly všechny naráz a nic by to nerozlišilo.

`↵` otevře (nález i soubor **odscrollují diff** na to místo, nález se navíc zvýrazní),
`⌘↵` otevře věc na GitHubu, `esc` zavře, `↑↓` chodí po řádcích a cyklí. Když nic nesedí, řekne
to — a napíše, **kde** se hledalo: paleta se nikoho nedoptává, hledá jen v tom, co je v paměti.
Proto jsou soubory jen z **otevřeného** PR (diff jiného v paměti není), zato nálezy ze **všech**;
odmítnuté se nenabízejí, protože nálezu, kterému nevěřím, není kam skákat.

**Filtr seznamu paletu nezužuje.** Filtr je zúžení seznamu, kdežto paleta je způsob, jak něco
najít — a hledání, ze kterého vypadne schovaný PR, je k nepotřebě právě tehdy, když je filtr
zapnutý.

**Akce, ne jen navigace**: pustit review na otevřený PR (nebo ho zrušit, když běží), přepnout
pohled na diff, složit panel s mým review, otevřít sekci railu, obnovit seznam, otevřít
nastavení. Nabízí se **jen to, co by něco udělalo** — bez otevřeného PR tedy nic, co na PR visí.
Kreslená zkratka je **vždycky ta skutečná** (`⌘2`, `⌘,`); návrh měl u „pustit review“ `⌘⇧R`, což
v aplikaci dělá něco jiného (pustit review na vše, co neběželo, z dashboardu), takže se
nenakreslila.

**Odsud nic neodchází.** Paleta nemá přístup k `ReviewPublishing` a nepřidává druhou cestu ven;
jediná věc, kterou pouští, je read-only reviewer.

### Odeslání review

**Dvě kliknutí, dvě různá tlačítka.** `Odeslat review…` v tabu `Moje review` nic neodesílá —
otevře potvrzení, ve kterém je vidět **celý payload**: verdikt, tělo tak, jak je napsané,
a každý řádkový komentář i s poli, se kterými odejde do API — `path`, `line` (u rozsahu
`start_line`) a `side`. Ta pole se berou **z téhož payloadu, který se posílá** (#178), takže se
výpis s odeslaným tělem nemůže rozejít; do #178 si je sheet skládal vlastní cestou a strana ani
začátek rozsahu v něm nebyly vůbec, přestože právě ony rozhodují, ke kterému kódu komentář sedne. Teprve
tlačítko tam zavolá GitHub. Zavřít se dá kdykoli a draft tím zůstane netknutý.

Ochrana stojí právě na tom výpisu, ne na obřadu: **žádné opisování názvu repa** a **žádný
druhý dialog nad sheetem**. Obojí se za týden odklikává poslepu a oslabí to i to první
potvrzení. Co zůstává, je pojmenování akce — tlačítko se jmenuje
`Odeslat APPROVE pro owner/repo#123` — a to, že **není výchozí**: Enterem se nic neodešle.

**`⌘⏎` otevře to potvrzení** (#151), a jenom to — odeslání zůstává druhé kliknutí na druhém
tlačítku, uvnitř sheetu žádná zkratka není. Dělá přesně totéž co `Odeslat review…` v panelu
včetně toho, kdy nedělá nic: nad draftem, který se odeslat nedá (chybí verdikt, prázdný
komentář, nepovolené repo), je zhasnutá stejně jako to tlačítko. Nad zastaralým draftem okno
otevře, protože se v něm dá přenést na nový commit.

Návrh verdiktu z nálezů stojí v potvrzení **vedle** toho odesílaného. Když je odesílaná hodnota
z návrhu, sheet to napíše (`Je to návrh z nálezů — ručně jsi verdikt nevybral.`), aby se v posledním
okně před odesláním nedala splést s mým rozhodnutím. A když se **moje** volba s návrhem rozchází
(schvaluju PR, u kterého reviewer hlásí blokující nález), řekne to nahlas.

Proč odeslat nejde, je vidět **předem** — vedle zakázaného tlačítka, ne až po pokusu:
chybějící verdikt, prázdný řádkový komentář, draft proti staršímu commitu, nebo repo, které
odesílat nesmí.

**Povolení je nastavení, ne konstanta**, a ve výchozím stavu je vypnuté. Zapíná se globálně
nebo u konkrétního repa (`Povoleno` / `Zakázáno` / `Podle globálního nastavení`) a platí hned,
bez restartu. Rozhoduje **jen** o tom, jestli se tlačítko vůbec nabídne: odesílá pořád člověk
potvrzením a proti commitu, který má před sebou. Přepnutí u repa se drží i po změně globálního
defaultu — repo, které si o zákaz řeklo, se tím nesmí tiše otevřít. Překlep v `config.json` se
sráží na zakázané, nikdy na povolené. **Platí to i pro odpovědi do vláken** — jedna brána pro
obojí, takže se nedá stát, že se do repa nesmí poslat review, ale komentář ano.

Po úspěchu se potvrzení **zavře samo**, draft zmizí (i z disku) a konverzace se načte znovu,
takže je moje review hned vidět v `Konverzaci`. Otevřené zůstane jen tehdy, když GitHub vrátí
stav, kterému aplikace nerozumí — tam je jediná zpráva ta, že se to má zkontrolovat ručně.
**Selhání draft nemaže**: chyba je vypsaná i s tím, co se s ní dá dělat, a dá se zkusit znovu.

Vlákna, jejichž řádek v aktuálním diffu **není** (typicky zastaralá po novém commitu), se
do kódu nekotví — jejich čísla platila pro starý head, takže by bublina sedla na cizí řádky.
Domov mají v záložce `Konverzace` spolu s review ostatních a komentáři pod PR, a je u nich vidět
kód, ke kterému se vážou — ten ze **starého** commitu, ne z dnešního.

Co se ve které verzi změnilo, ukazuje **okno `Novinky v PRism`** přímo v aplikaci (✨
v toolbaru, nebo menu aplikace): vlevo celá historie vydání, vpravo release notes
té vybrané. **Po aktualizaci se otevře samo**, jednou, s vybranou nejnovější verzí — jinak
by o novinkách nikdo nevěděl. Podrobnosti jsou v sekci [Novinky](#novinky) níž; totéž je
i v [releases](https://github.com/ondrajodas/PRism/releases) na GitHubu. Kde projekt je
jako celek, říká [`docs/stav.md`](docs/stav.md), ne release notes: ten stav by v nich
zastaral hned další verzí.

- [Návrh (specifikace)](docs/superpowers/specs/2026-07-31-prism-design.md) — plný
  návrh včetně záznamu rozhodnutí a zamítnutých alternativ
- [`docs/navrh.md`](docs/navrh.md) — kde je **vizuální** návrh (mockup) a jak se s ním
  pracuje; co mění vzhled, se do něj kreslí a schvaluje dřív, než na to vznikne issue
- [`docs/claude-cli.md`](docs/claude-cli.md) — ověřené chování `claude` CLI
- [`docs/github-review-api.md`](docs/github-review-api.md) — ověřené chování zápisového
  review API GitHubu; podklad pro odesílání review (M6)
- [CLAUDE.md](CLAUDE.md) — pravidla pro práci v tomto repu
- [`docs/architektura.md`](docs/architektura.md) — co který modul drží a co se u něj nemá
  rozbít
- [`docs/testovani.md`](docs/testovani.md) — co se u které oblasti testuje a proč zrovna to
- [`docs/stav.md`](docs/stav.md) — co je hotové a co zbývá
- [`docs/paralelni-vyvoj.md`](docs/paralelni-vyvoj.md) — jak se vyřizuje seznam issues naráz

## Jak to funguje

1. **Polling GitHubu** přes `gh` — hledají se PR, u kterých je po mně požadované review
   (`review-requested:@me`). Repozitáře nejsou pevný seznam, může přijít cokoli.
2. **Checkout na vyžádání** — repo se naklonuje do vlastní cache aplikace jako bare
   partial clone a přidá se detached `git worktree` na head commitu daného PR.
   **Vlastních** klonů na disku se aplikace nikdy nedotkne.
3. **Review** — nakonfigurované skilly se spustí jako paralelní headless session
   Claude Code v tom worktree, omezené na read-only nástroje. Prompt si o skill říká
   nástrojem `Skill` výslovně, takže v konfiguraci jsou jeho id (`plugin:skill`), ne
   slash commandy. Které to jsou, může záviset
   na programovacím jazyce repa; ten se odhaduje z `git ls-files`. Spouští se **tlačítkem**,
   nebo samo, když je repo v automatickém režimu — ten se zapíná globálně i zvlášť pro každé
   repo a výchozí je manuální, aby neznámé repo nespálilo panel session bez dozoru.
   **Automat utratí session, teprve když se změnil head commit**, takže komentář na PR ho
   nespustí, a hlídá ho denní limit.
4. **Sběr nálezů** — z `ReportFindings` tool callů ve `stream-json` event streamu.
   Strukturovaná data, ne parsování textu.
5. **Zobrazení** — diff v plné šířce s nálezy jako bubliny na svém `file:line`, plus
   řaditelná tabulka pro nálezy, které ke konkrétnímu řádku nepatří (chybějící testy,
   architektonické poznámky).

6. **Notifikace** — aplikace dá vědět, i když se do ní nikdo nedívá: o novém PR ve frontě
   a o doběhlém review. Klik na notifikaci ten pull request vybere a dá okno dopředu.

**Co nedoběhlo, se neztratí.** Když se aplikace zavře, ptá se — a když se ukončení potvrdí,
**běžící session zabije** a čeká, dokud po nich nezůstane běžet nic. Bez toho `claude` aplikaci
přežil: osiřelý proces počítal tokeny za review, které už nemá komu doručit, a držel pracovní
strom v cache (změřeno, dvě takové session běžely čtyři dny). Ze zaseknuté session přitom nesmí
vzniknout aplikace, která se nedá zavřít, takže čekání má strop dvou sekund.

Nálezy z takového běhu se pak **dotáhnou z transcriptu**, který si `claude` vede na disku: běh se
poznamená, jakmile nahlásí id session, a po startu se z něj přečte, co stihl. Platí to i pro pád
aplikace nebo `kill`, na které se ptát nedá — zavření aplikace se od nich v tomhle záměrně neliší.
Takový výsledek je v řádku `přerušeno`, ne `timeout` ani `čisté` — nedoběhl, takže se z něj nesmí
soudit, že je hotovo. Zrušení review člověkem je proti tomu jiná odpověď: tam se nedotahuje nic,
protože o ty nálezy si nikdo neřekl.

Nálezy jsou klíčované head commitem PR. Když přijdou nové commity, předchozí nálezy se
označí jako zastaralé — nezobrazují se proti kódu, který už neexistuje.

**A dá se u nich zjistit, co nové commity spravily** (#150). Nad zastaralými nálezy se v hlavičce
nabídne `Zkontrolovat nálezy`: pustí to session, která dostane **uložené nálezy z předchozího
commitu** jako seznam a projde je proti pracovní kopii na hlavě PR — vlastní prompt, tytéž
read-only nástroje jako review. U každého nálezu pak stojí odznak `kontrola: vyřešeno`,
`kontrola: pořád platí` nebo `kontrola: nejasné` a k němu věta, jak k tomu běh došel; v hlavičce
je souhrn (`3 vyřešené, 1 pořád platí, 1 bez odpovědi`).

Vyřešený nález je poznat na první pohled: **shrnutí je přeškrtnuté** a v odznaku závažnosti stojí
`vyřešeno`. Přeškrtne se u toho jen text nálezu, ne celý řádek — celá plocha se ztlumí jedině
u nálezu, který jsem **odmítl** sám, a ty dva stavy se nesmí plést. A když nález blokuje, zůstává
u něj `blokuje` i nadále: „vyřešeno“ je tvrzení modelu, kdežto to, že se PR pořád nemerguje, je fakt.

Tři věci, které z toho **neplynou**. Odznak nálezy **nemaže ani neschovává** — je to tvrzení
modelu, ne fakt, a sundat nález smí jedině odmítnutí (#113), za kterým stojí člověk. Kontrola se
**nenabízí**, dokud není uložený záznam proti staršímu commitu, protože bez nálezů by se session
neměla na co ptát. A **platí jen pro tu hlavu, proti které běžela**: po dalším commitu odznaky
zmizí a v hlavičce zbyde věta, že se dá pustit znovu.

### Notifikace

Co přijde a co v tom bude:

| Kdy | Co uvidím |
|---|---|
| Nový PR ve frontě | `Nový PR k review — owner/repo#123` a název PR |
| PR, který jsem už reviewoval, se vrátil | `Znovu požádáno o review — owner/repo#123` a název PR |
| Víc nových PR naráz | Jeden souhrn: `4 nové PR k review` a tři z nich jménem plus `a 1 další` |
| Víc naráz, něco z toho znovu | `4 PR k review (1 znovu)` |
| Review našlo nálezy | `3 nálezy · 1 blokuje`, pod tím nejzávažnější nález (`correctness: …`) a na třetím řádku `owner/repo#123` |
| Review našlo nálezy, ale nic nezastavuje merge | `3 nálezy · nic neblokuje` |
| Review je čisté | `Čisté review` a `Reviewer nenašel žádný nález.` |
| Review se nepovedlo | `Review se nepovedlo` a pod tím důvod, se kterým se dá něco dělat — spadlá session, timeout bez nálezů, selhaná pracovní kopie |

**Titulek odpovídá na „mám k tomu jít hned?“** (#200) — proto v něm je počet nálezů a kolik
z nich blokuje, ne jméno pull requestu. To je až na třetím řádku; v banneru je vidět taky
(změřeno: vejdou se čtyři řádky těla), a co se do něj nevejde, je celé v Oznamovacím centru.
Dlouhý souhrn nálezu se proto krátí sám — bez toho by systémový ořez sebral i řádek
s identifikací.

**Jedna notifikace na pull request**, ne jedna na skill: reviewery jedou paralelně a tři
hlášky za jednu věc jsou tři vyrušení. Nový výsledek review přepíše ten starý, aby vedle
`3 nálezy` nezůstala viset stará hláška `Čisté review`. Notifikace o témž PR systém řadí
k sobě.

**Co se hlásí, se nastavuje** — stránka `Notifikace` v okně nastavení: hlavní vypínač a čtyři
události (nový PR, review s nálezy, čisté review, selhání). Ve výchozím stavu je zapnuté všechno.
S vypnutým hlavním přepínačem se aplikace **nezeptá ani na systémové oprávnění**.

**Re-review se pozná od novinky.** U pull requestu, který jsem už někdy reviewoval, není
„nový PR“ pravda — a je to jiné očekávání: u nového jde o první přečtení, u re-review o to,
co se od mého review změnilo. Že ho znám, se pozná z uložených nálezů; zahozený záznam z něj
udělá zase novinku, protože zahození znamená „tenhle výsledek je k ničemu“.

**Co dneska stálo review, je vidět ve stavovém řádku** — cena za dnešek, ruční i automatická
review dohromady, počítáno od půlnoci a přežívá to restart. Rozpočet v penězích aplikace nemá:
`autoRunsPerDay` omezuje **počet PR**, ne sessions ani dolary, a je to vědomé — nejdřív se má
pár týdnů koukat na skutečné číslo a teprve pak rozhodnout, jestli je brána potřeba. Součet, do
kterého se nepodařilo započítat všechno (zabitý nebo přerušený běh cenu nenahlásí), je označený
`≥`: je to **dolní odhad**, ne úplná částka.

**Že notifikace fungují, je vidět ve stavovém řádku** — vlevo od puntíků služeb je zvonek
s časem posledního doručení. `zatím nic` znamená, že se od spuštění nic neohlašovalo (a nic se
tím netvrdí o tom, jestli to funguje), `vypnuto` že jsou vypnuté v nastavení. Čas posune jedině
**doručená** notifikace: odmítnuté oprávnění ani selhání systému ho nechají být, jinak by řádek
tvrdil, že to chodí, zrovna když nechodí. Drží se v paměti, takže po restartu začíná znovu —
je to odpověď na „funguje mi to teď“, ne historie.

**Po prvním spuštění nepřijde lavina.** Aplikace si drží snímek poslední fronty, takže PR, která
tam byla, než začala hlídat, za nová nepovažuje. Ohlásí se až devátý.

Notifikace fungují jedině z `/Applications` — `bin/run.sh` tam aplikaci instaluje sám, viz
*Build*.

## Novinky

Okno `Novinky v PRism` (menu aplikace hned pod `O aplikaci PRism`, nebo ✨ v toolbaru)
je jedno okno nad jedněmi daty: vlevo seznam všech vydání s tagem, názvem a časem vydání,
vpravo release notes té vybrané, vykreslené jako Markdown. Dvě obrazovky — „co je nového“
zvlášť a „historie“ zvlášť — by se dřív nebo později rozešly. **Čas u data je tam schválně:**
verzí vyjde za jeden den klidně šest, takže samotné `5. 8. 2026` o pořadí neříká nic.

**Po aktualizaci se otevře samo, jednou**, s vybranou nejnovější verzí; vydání novější než to
naposledy viděné mají v seznamu odznak `nové`. Jinak by o novinkách nikdo nevěděl — a otevřít
se dá kdykoli — z menu aplikace nebo tlačítkem v toolbaru hlavního okna, hned vedle
ozubeného kola. Zavírá se **Escem** i ⌘W: je to okno na čtení, takže v něm není co ztratit.

**Otevře se vystředěné v hlavním okně**, ne doprostřed obrazovky — otevírá se z jeho toolbaru,
z menu a po aktualizaci, takže tam se člověk v tu chvíli kouká; na velkém (nebo druhém) monitoru
by jinak vyskočilo někde vedle. S hlavním oknem u kraje obrazovky se zarovná zpátky na viditelnou
plochu a bez hlavního okna se otevře tak, jak rozhodne systém. Stejně se od začátku středí okno
nastavení — je to jeden mechanismus pro obě.

Odsunuté okno **v rámci běhu zůstane, kam si ho dáš**, a po restartu je zpátky ve středu. Okno,
které pod rukama uskakuje, je horší než okno mimo střed, takže se pozice srovnává jen při
otevření, ne při vytažení dopředu.

**A dokud je otevřené, zůstává před hlavním oknem** — stejně jako nastavení a tou samou cestou.
Nad cizí aplikací neplave: s odchodem PRismu do pozadí spadne na normální hladinu a s návratem je
zpátky vpředu. Zavřené okno se nevrací.

Historie se tahá **jedním voláním** `gh` z vlastního repa aplikace (tělo releasu je rovnou
v seznamu, takže se na jednotlivou verzi nechodí zvlášť) a drží se v paměti do konce běhu:
jednou při startu kvůli tomu, jestli něco přibylo, a pak už jen z paměti. V pollingu ani na
pozadí se aplikace na nic neptá. Bez sítě je v okně **důvod a tlačítko `Zkusit znovu`**, ne
prázdný seznam — „nepovedlo se to načíst“ a „žádná vydání nejsou“ znamenají opak.

Že se vydání ukázalo, si aplikace poznamená **až ve chvíli, kdy je okno na obrazovce** — ne
když se to rozhodne. Kdyby se okno neotevřelo, zůstane značka na místě a příští spuštění to
zkusí znovu; opačné pořadí znamená vydání ohlášené „na papíře“, které se neukáže nikdy.

**Okno mluví o tom, co vyšlo na GitHubu, ne o spuštěném buildu**, a nevypisuje proto číslo
verze. Verze v bundlu (`MARKETING_VERSION`) tagy nikdy nesledovala, takže by tvrdila `0.1`;
a u lokálního buildu se ty dvě věci rozcházejí v obou směrech. Aplikace si místo toho pamatuje
poslední **viděný tag** a nabízí, co je novější. **První spuštění mlčí** a značku jen založí —
jinak by po startu vypadala jako nová celá historie.

## Klíčová rozhodnutí

| | |
|---|---|
| **Reviewery** | Běží nezávisle a paralelně. Texty nálezů se mezi nimi neslučují — nesouhlas dvou reviewerů je informace. Shoda na stejném `file:line` se označí odznakem `2×`. |
| **Jazyk nálezů** | Volba v nastavení, ne natvrdo. Řeší se **překladem po doběhnutí**, ne instrukcí v promptu: psát rovnou česky měřitelně ubírá nálezy. Reviewer píše v jazyce, ve kterém je nejsilnější; jazyk je věc zobrazení. |
| **Závažnost** | Aplikace nevymýšlí vlastní škálu. Seskupuje podle `category` z výstupu reviewera a odvozuje jediný blokující boolean (`verdict == CONFIRMED` a `category` v blokující sadě). Z toho vypadne návrh verdiktu. |
| **Falešně pozitivní nálezy** | Normální provoz, ne chyba. Jeden nález se dá odmítnout jako `neplatný` nebo `irelevantní` a ostatní platí dál; do verdiktu a do řádku seznamu se nepočítá, ale z okna nezmizí — sbalí se. Označení bydlí na záznamu, ne na nálezu, aby ho nesmazalo opakované review týmž skillem, a platí jen pro ten commit: nálezy jsou klíčované head commitem. |
| **Oprávnění** | Reviewer je read-only: `Write` ani `Edit` nemá povolené a `git push` s `gh` jsou výslovně zakázané. Ověřeno spuštěním, včetně toho, že zákaz platí i na `git push` s vypsanou URL — bez něj by session uměla pushnout do mého repozitáře, protože `origin` v cache míří na skutečné repo. |
| **Token** | Aplikace na GitHub token nikdy nesahá. Autentizace je delegovaná na `gh`, který credential drží v keychainu. |
| **Konfigurace** | Tři úrovně: globální default, sada podle programovacího jazyka repa a override per repo (režim auto/manual, sada skillů, blokující kategorie). Co si repo neřekne, bere globálně — proto je override `nil`, ne prázdná hodnota. Edituje se ručně v `config.json` i oknem nastavení; obojí píše do téhož souboru. |
| **Odesílání na GitHub** | Platí pro review, odpovědi do vláken i komentáře pod PR. Ve výchozím stavu vypnuté a zapíná se v nastavení, globálně i per repo. Brána je jedno místo (`PublishScope`), na které se ptá publisher i okno — jinak by tlačítko slibovalo něco, na čem odeslání skončí. Proti omylu nechrání seznam rep, ale potvrzení s úplným výpisem payloadu a kontrola, že se posílá proti commitu, který jsi viděl. |
| **Notifikace** | Slévají se nad seznamem z jednoho tiku pollingu, ne přes vlastní čekací okno — tik dodá všechna nová PR naráz, takže se slévá právě to, co se stalo mezi dvěma tiky, a nepotřebuje to stav ani zdržení hlášky. Vypnout je jde po událostech; s vypnutým hlavním přepínačem se nežádá ani o systémové oprávnění, protože dialog za něco vypnutého je dialog za nic. |
| **Novinky v aplikaci** | Okno mluví o tom, co vyšlo na GitHubu, ne o spuštěném buildu — verze v bundlu tagy nikdy nesledovala, takže by tvrdila `0.1`. Značka je poslední **viděný tag** v předvolbách aplikace (stav aplikace, ne nastavení k editaci) a historie se drží v paměti do konce běhu: disková cache by dala offline režim, ale je to další store s vlastním úklidem. |
| **Rozměry v okně** | Šířka se v zanořeném stromu **předává, ne vyjednává**. `frame(maxWidth: .infinity)` na každé úrovni zanoření stojí ~5,5× na úroveň, takže okno na PR s 2000 změněnými řádky tuhlo dvacet minut na plném CPU — a to v obou tabech, protože o obsah vůbec nešlo, jen o tvar stromu. Šířka se proto měří jednou na hranici obsahu tabu a posílá dolů. Pružná výška v líném seznamu je tatáž chyba a řešila se dřív u dvojice řádků diffu. |
| **Dostupnost služeb** | Jede na skutečném provozu, ne na sondě: `gh auth status` na timeru by stál spawn procesu a přístup do keychainu — a projde i tehdy, když skutečné volání selže na rate limitu. Status pages jsou proti tomu levné (`components.json` s `ETagem`) a odpovídají na to, co z volání nezjistíme: jestli je problém na jejich straně. |

## Požadavky

- macOS 26, Xcode 26
- [`gh`](https://cli.github.com) — přihlášený (`gh auth login`)
- `claude` — Claude Code CLI
- `git`

Kromě těch tří binárek chodí aplikace na síť **jediným vlastním voláním**: stahuje si stav
komponent ze status pages GitHubu a Claude pro stavový řádek. Jsou to veřejné endpointy, jde
o `GET` bez tokenu a bez cookies, a když se nepovede, aplikace o něj nezavadí — puntík se
pak řídí jen skutečnými voláními. Vše ostatní jde přes podprocesy `gh`, `git` a `claude`.

Aplikace binárky hledá absolutní cestou, protože GUI aplikace spuštěná z Finderu nedědí
`PATH` z shellu. Nejdřív zkusí známá místa (`/opt/homebrew/bin`, `/usr/local/bin`,
`/usr/bin`, `~/.local/bin`), a co v nich není, dohledá v `PATH` login shellu. Ten čte
`.zshenv`, `.zprofile` a `.zlogin`, ale **ne `.zshrc`** — kdo má nástroj mimo známá místa
a `PATH` doplněný jen v `.zshrc`, musí cestu přidat do `.zprofile`.

Když něco chybí, aplikace se nespustí do prázdna — ukáže blokující obrazovku se **všemi**
problémy naráz: u každého nástroje cestu, kde se našel, nebo k čemu je a čím se instaluje.
U `gh` navíc kontroluje přihlášení. Po instalaci stačí `Zkusit znovu`, restart není
potřeba.

## Build

Spustit aplikaci — jeden příkaz, buildne v Debug, nainstaluje do `/Applications` a otevře
okno:

```bash
./bin/run.sh
```

Samotný build a testy:

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex build
```

```bash
xcodebuild -project PRism.xcodeproj -scheme PRism -derivedDataPath build.noindex test
```

`bin/run.sh` buildí do `build.noindex/` v repu (`-derivedDataPath`), aby byla cesta k `.app`
předvídatelná; složka je gitignorovaná. Před spuštěním ukončí předchozí instanci.

**Přípona `.noindex` v názvu je funkční, ne kosmetická.** Bez ní si LaunchServices kopii
v `build/` samo zaregistruje — po odregistrování je do 25 vteřin zpátky — a ve Spotlightu
i v `Otevřít v aplikaci` pak stojí dva PRismy se stejným jménem, ze kterých se nedá vybrat.
Spotlight `.noindex` složky neprohledává, takže se registrace sama nevrátí; Xcode ji ale na
konci buildu přidá výslovně a `xcodebuild test` navíc testovacího hosta **spouští**, čímž
ho zaregistruje taky. `bin/run.sh` proto po instalaci tu jednu cestu odregistruje — a protože
do `build.noindex/` míří i testy, uklidí tím i po nich. Proto ten přepínač patří i k nim.

Hotový bundle pak **nainstaluje do `/Applications` a spustí odtud**, protože jinde
nefungují notifikace: z `build.noindex/` i z `~/Applications` vrací systém
`Notifications are not allowed for this application` a stav oprávnění zůstane `denied` —
bez dialogu a bez záznamu v Nastavení systému, takže se to nedá ani ručně povolit.
Ověřeno i na minimální cizí aplikaci s jiným bundle identifikátorem, takže to není
vlastnost PRismu, ale toho, odkud je aplikace spuštěná.

Skript odmítne přepsat bundle, který se hlásí cizím identifikátorem, a když se instalace
nepovede, radši nespustí nic — spuštěná stará verze z `/Applications` je přesně ta past
„koukám na starý build“.

### Paralelní vývoj — sloty

Vývoj se zdržuje čekáním, takže se dá pracovat ve víc oknech naráz. Překáží tomu jediná věc:
`bin/run.sh` bez dalšího zařízení instaluje pořád do stejného `/Applications/PRism.app`,
ukončuje běžící instanci a všechny instance sdílejí jednu cache. Druhé okno by tedy
sestřelilo aplikaci, se kterou se zrovna pracuje, a rozestavěný build by sáhl na uložené
nálezy a rozdělané drafty.

Řeší to **slot**. Pracovní strom se založí skriptem:

```bash
./bin/worktree.sh a issue-231-neco
cd ../PRism-a && ./bin/run.sh
```

Vznikne strom `../PRism-a` s novou branchí z `origin/main` a se souborem `.prism-slot`.
Ten pak čte `bin/run.sh` a odvodí z něj celou identitu instance:

| | hlavní strom | slot `a` |
|---|---|---|
| bundle ID | `com.ondrajodas.prism` | `com.ondrajodas.prism.a` |
| v `/Applications` | `PRism.app` | `PRism-a.app` |
| jméno v Docku | `PRism` | `PRism-a` |
| cache | `~/Library/Application Support/PRism/` | `…/PRism-a/` |
| build | `build.noindex/` v tom stromu | vlastní, cesta je relativní |

Bez souboru `.prism-slot` se nemění vůbec nic, takže hlavní strom zůstává tou aplikací,
která se používá. Slotů může být víc; slot je libovolný řetězec z písmen, číslic a pomlček,
protože jde do bundle ID.

**Kořen cache si aplikace odvozuje z `CFBundleName`**, ne z konstanty — proto má slot vlastní
konfiguraci, klony i uložené nálezy. Je to ta podstatná část: build s rozbitou persistencí
nemá jak smazat rozdělaný draft, tedy ručně psanou práci.

Konfigurace se do slotu zkopíruje, ale **očištěná** — bez povoleného odesílání, bez
notifikací a bez automatického spouštění review, a to **na obou úrovních**: globálně
i u každého repa. Odesílání proto, že výchozí stav je vypnuto a u rozestavěného buildu to
platí dvojnásob; notifikace proto, že slot má vlastní `announced.json` a ohlásil by jako nové
úplně všechny PR ve frontě; automat proto, že by spouštěl review, které nikdo nečte a za které
se platí. Když na stroji není `jq`, konfigurace se **nezkopíruje vůbec** — kopírovat ji
neočištěnou by znamenalo předat slotu povolené odesílání.

Očistu drží **`bin/slot-config.sh`** a je to jediné místo, kde existuje (#262):

```bash
./bin/slot-config.sh      # slot se přečte z .prism-slot v tomhle stromě
./bin/slot-config.sh d    # slot výslovně; takhle to volá bin/worktree.sh
```

Samostatný skript je proto, že do slotu se nedostane každý přes `worktree.sh` — subagent
v paralelním vývoji má strom od harnessu, takže si očistu do #262 opisoval, a dvě kopie
znamenají, že se příští oprava udělá jen v jedné. Přesně to se stalo: `mode` se čistil
globálně, ale ne u rep, takže per-repo override `mode: automatic` očistou prošel a přebil
globální `manual` (per-repo override je přednější — je to celý smysl `resolved(for:)`).
Slotová aplikace si sama pustila review za **2,80 $ v jednom slotu a 1,16 $ v dalším**.

Tři vlastnosti, kterými se ta chyba splácí:

- **Vypíše, co našlo.** Repa s automatem jmenovitě, počet rep s povoleným odesíláním — očista,
  která proběhne potichu, se nedá zkontrolovat.
- **Ověří výsledek, ne filtr.** Po přepsání se v datech hledá zbylý automat a povolené
  odesílání; když se něco najde, **nezapíše se nic** a skript skončí nenulově.
- **Existující konfiguraci slotu nepřepíše tou hlavní** (proklikané nastavení je ruční práce),
  ale **pustí na ni tutéž očistu** — sloty se používají opakovaně a v cache může ležet
  konfigurace z doby, kdy očista automat u repa nechytala.

Co se čistí a co ne, je vyjmenované v komentáři skriptu — **celý `GlobalConfig`**, včetně
klíčů, které se nechávají být, a důvodu u každého. Nový klíč, který má obě úrovně
(`GlobalConfig` i `RepositoryConfig`), do toho výčtu patří, i kdyby se nakonec nečistil.

Po mergnutí branche se strom i cache slotu uklidí:

```bash
git worktree remove ../PRism-a
rm -rf ~/Library/Application\ Support/PRism-a
```

### Ikona

Ikona je **generovaná z kódu**, ne obrázek přinesený zvenčí:

```bash
swift bin/make-icon.swift                    # nasazená varianta
swift bin/make-icon.swift split              # druhá barevná varianta
swift bin/make-icon.swift split /tmp/náhled  # jen vykreslit, bez zásahu do repa
```

Motiv jsou znaky obou nástrojů rozpůlené diagonálou zleva zdola doprava nahoru — vlevo
nahoře Claude, vpravo dole GitHub. Skládá se z **oficiálních** značek (`bin/icon-sources/`,
favicony obou služeb), takže se nekreslí zpaměti; barvy jsou z nich taky. Nasazená je
varianta s krémovým znakem na oranžové, druhá (Claude v původních barvách) zůstává v repu,
aby se dalo přepnout.

**Malé velikosti nejsou zmenšené velké** — pod 64 px se kreslí hruběji, protože ve 16 bodech
ikona skončí v přepínači aplikací a jemná kresba se tam slije.

Po překreslení je potřeba **restartovat Dock** (`killall Dock`), jinak se dál dívá na starou
ikonu z cache a vypadá to, že se nic nezměnilo.

Aplikace běží **bez App Sandboxu** — spouští `git`, `gh` a `claude` a zapisuje do vlastní
cache.

### Podpis

Výchozí podpis je ad-hoc (`CODE_SIGN_IDENTITY = -` v `Signing.xcconfig`), takže build
nepotřebuje Apple účet ani tým a projde na jakémkoli stroji bez přípravy. Developer ID
podpis a notarizace by byly potřeba až pro distribuci.

Ad-hoc podpis ale **nemá stálou identitu**: každý build dá jiný otisk, takže macOS považuje
aplikaci pokaždé za jinou a povolení udělená přes TCC se na novou verzi nevztahují. Prakticky
to znamená dotaz na přístup do **Stažených souborů** po každém rebuildu. Aplikace tam
nesahá — vyvolává ho `claude`, který si při startu bere prostředí z uživatelova shellu, a ten
načte `~/.zshrc` sourcující Google Cloud SDK rozbalený v `~/Downloads`. Dotaz se proto objeví
až při spuštění review, ne po startu aplikace.

Stálou identitu dá vlastní certifikát. Vyrobí ho jednorázově:

```bash
./bin/setup-signing.sh
```

Skript vytvoří self-signed certifikát typu *Code Signing* s názvem `PRism Local` v login
keychainu a napíše `Signing.local.xcconfig` s jeho jménem; odtud si ho přes `#include?`
vezme `Signing.xcconfig`, takže se podepisuje stejně ve `bin/run.sh`, v `xcodebuild` i v
Xcode. Ten soubor se **necommituje** — jméno certifikátu je vlastnost stroje, ne repa, a
bez něj se spadne zpátky na ad-hoc. Systém si přitom může říct o přihlašovací heslo —
jednou při zápisu do nastavení důvěry (bez něj se self-signed certifikát mezi platné
identity nezapočítá) a při prvním buildu ještě o přístup ke klíči, kde stačí kliknout na
*Vždy povolit*. Ten druhý dotaz odbourá předem heslo zadané na řádku, který skript nabízí;
přeskočit ho jde Enterem.

Že je podpis stálý, se ověří takhle:

```bash
codesign -dv --verbose=4 build.noindex/Build/Products/Debug/PRism.app
```

Ad-hoc build hlásí `Signature=adhoc`, podepsaný `Authority=PRism Local`. Na ad-hoc podpis
upozorní i `bin/run.sh`, protože jinak je příčina vracejících se dotazů neviditelná.
Certifikát se odstraní přes `security delete-identity -c "PRism Local"`.

## Struktura

```
PRism.xcodeproj/          Xcode projekt (shared scheme je verzovaný)
App/                      zdrojáky aplikace — target PRism
  Models/                 doménové modely: PR, identifikátory, stav review
  Environment/            přístup ke stroji: hledání binárek, podprocesy, preflight, notifikace, předvolby
  GitHub/                 čtení PR a konverzace přes gh CLI: gateway, typované chyby, tvar výstupu
  Checkout/               vlastní cache repozitářů: klony, worktrees, úklid
  Config/                 config.json: globální default, override per repo, čtení a zápis
  Diff/                   parsování unified diffu na soubory, hunky a řádky, slití do dvojic pro pohled
                          vedle sebe a porovnání uvnitř přepsané dvojice (word-level diff)
  Health/                 dostupnost služeb pro stavový řádek: status pages, signály, monitor
  Markdown/               vykreslení Markdownu z GitHubu: bloky, inline HTML od botů
  Policy/                 čisté funkce: slučování zdrojů, řazení, stav řádku, odhad jazyka, hledání v paletě
  Publish/                jediná cesta ven: odeslání review, odpovědi do vláken a jejich vyřešení, komentář pod PR, brána z nastavení
  Review/                 spuštění session claude a překlad stream-json na nálezy
  Polling/                obnovování seznamu v intervalu, backoff, neaktuální data
  Store/                  AppStore — stav, který kreslí okno (stav v AppStore.swift, metody v AppStore+*.swift);
                          ReviewStore a ReviewDraftStore — nálezy a rozdělaná review na disku
  Syntax/                 obarvení kódu: jazyky, tokenizace, paleta, zapamatování výsledků
  Support/                sdílené drobnosti bez příslušnosti k modulu
  Views/                  SwiftUI obrazovky
    ReleaseNotes/         okno s novinkami — historie vydání a release notes vybrané verze
    Settings/             okno nastavení (⌘,) — sedm stránek v boční navigaci (#177)
  Assets.xcassets/        ikona aplikace (generovaná, viz bin/make-icon.swift)
Tests/                    unit testy — target PRismTests
  Models/                 testy modelů + pomocníci na Codable round-trip
  Environment/            testy Environment vrstvy + fakes
  Checkout/               testy klonování — proti fake runneru i skutečnému gitu
  Config/                 testy čtení, zápisu a slučování konfigurace
  Diff/                   testy parseru diffu proti skutečným výstupům gh pr diff a word-level rozdílu
  Health/                 testy status pages, monitoru dostupnosti a HTTP vrstvy
  Markdown/               testy parseru Markdownu (invariant: nic se neztratí) a HTML od botů
  GitHub/                 testy gateway a klasifikace chyb gh
  Policy/                 testy čistých funkcí
  Review/                 testy parseru a runneru proti skutečným streamům
  Polling/                testy pollingu proti fake gateway a fake času
  Publish/                testy odesílání — hlavně že se při neshodě neodešle nic
  Store/                  testy AppStore a persistence nálezů
  Views/                  testy řádků tabulky, modelu okna nastavení a novinek
  Syntax/                 testy detekce jazyka a obarvení kódu
  Support/                testy sdílených drobností
  Fixtures/gh/            skutečné výstupy gh z veřejných repozitářů (JSON i diffy)
  Fixtures/stream-json/   skutečné stream-json výstupy claude z reálných běhů
  Fixtures/statuspage/    skutečné components.json ze status pages (a jeden s dopsaným incidentem)
bin/run.sh                build + spuštění jedním příkazem
bin/worktree.sh           pracovní strom se slotem — paralelní vývoj vedle běžící aplikace
bin/slot-config.sh        očištěná konfigurace do cache slotu (jediné místo, kde ta očista je)
bin/copilot-review.sh     vyžádání Copilot review na PR
bin/setup-signing.sh      jednorázová příprava stálého podpisu (self-signed certifikát)
bin/make-icon.swift       vykreslí ikonu do asset catalogu (bez závislosti, přes ImageRenderer)
bin/icon-sources/         oficiální značky, ze kterých se ikona skládá
Info.plist                název aplikace, verze, minimální systém
PRism.entitlements        vypnutý App Sandbox
Signing.xcconfig          podpis: ad-hoc default + volitelný Signing.local.xcconfig
docs/architektura.md      podrobnosti po modulech
docs/testovani.md         co se u které oblasti testuje
docs/navrh.md             kde je vizuální návrh (mockup) a jak se s ním pracuje
docs/stav.md              co je hotové a co zbývá
docs/claude-cli.md        ověřené chování claude CLI (flagy, tvar eventů)
docs/github-review-api.md ověřené chování zápisového review API GitHubu (spike k M6)
docs/superpowers/specs/   návrh a specifikace
CLAUDE.md                 pravidla pro práci v repu
README.md                 tento soubor
.gitignore                artefakty Xcode buildu, SPM, .DS_Store, Signing.local.xcconfig
```

`App/` a `Tests/` jsou v projektu napojené jako **buildable folders** — obsah se do
targetu bere z filesystému. Nový soubor stačí vytvořit, do `project.pbxproj` se nic
nezapisuje. `Info.plist` a entitlements proto leží v kořeni: cokoli uvnitř `App/`, co
není zdroják, by se zkopírovalo do `.app` jako resource.

Repo, Xcode projekt, target, produkt i to, co appka ukazuje v Docku, se jmenují stejně —
`PRism`. Swiftový modul taky (`PRODUCT_MODULE_NAME`), takže testy dělají
`@testable import PRism`.
