# PRism

Nativní macOS aplikace, která hlídá GitHub pull requesty, u kterých jsem požádán o
review, spouští na ně review skilly Claude Code a nálezy zobrazuje vedle diffu.

Aplikace je **orchestrátor a prohlížeč** — nemá vlastní review logiku. Veškerá analýza
žije ve skillech Claude Code; aplikace rozhoduje, kdy spustit který skill a kde, odchytí
strukturovaný výstup a vykreslí ho.

Hranol rozloží jeden paprsek na spektrum. Tahle aplikace dělá totéž s pull requestem —
pustí na něj několik nezávislých reviewerů a jejich nálezy schválně neslévá do jednoho
názoru.

> **Na GitHub vede jediná cesta a otevírá ji jen člověk.** Aplikace umí odeslat review
> a odpovědět do vlákna, ale výhradně přes jeden modul a jen na výslovný pokyn — review
> navíc proti commitu, který jsi opravdu viděl. Nic se neodesílá samo — ani návrh verdiktu,
> ani reviewer.
>
> **A jedině tam, kde se to povolilo.** Odesílání je ve výchozím stavu vypnuté — zapíná se
> v nastavení, globálně nebo u jednoho repa. Dokud si o to někdo výslovně neřekne, neodejde
> nikam nic.

## Stav

**Aplikace dělá to, kvůli čemu vznikla: pustí review na moje skutečné PR a ukáže nálezy.**

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
repu). Že je filtr zapnutý a kolik schovává, je vidět na ikoně **bez otevírání nabídky**, protože
skrytý filtr je způsob, jak přijít o review; a když schová všechno, řekne to a nabídne se vypnout —
zelené „Žádné PR k review“ by nad zapnutým filtrem tvrdilo opak pravdy.

Filtr je **pohled, ne seznam**: nic se tím nepřestane stahovat, nezahodí se diffy ani rozdělaná
review, běžící review běží dál, automat plánuje dál a okno nastavení pořád vidí i schované repo.
**Nepřežije restart** — je to jediné, co umí PR schovat úplně, a zmizelý PR vypadá jako vyřízený.
Na trvalé schování jsou **zdroje** v nastavení (search dotaz umí i `-author:`), což je změna toho, co
se stahuje.

U vybraného PR je tlačítko **Spustit review**. Za ním se stane tohle: dotáhne se head
commit, připraví se odpojený pracovní strom a v něm se spustí headless session Claude Code
omezená na čtení. Řádek mezitím ukazuje `ve frontě · clone` → `běží 0/1` → `čisté` nebo
`N nálezů`; běh jde kdykoli zrušit. Nálezy se uloží na disk, takže přežijí restart, a
v detailu je dole lišta s **návrhem verdiktu** (`approve` / `request changes` / *není
z čeho soudit*) a rozbaleným seznamem nálezů po kategoriích, s odznakem u těch blokujících.
Kliknutím na nález diff odskočí na jeho `file:line`.

Nad záložkami je **hlavička s tím, kam se to merguje** (#174): stav PR jako chip, `autor chce
sloučit větev → base`, `owner/repo#číslo` a odkaz na GitHub. Větve se do okna dostaly až s #174 a je to první věc,
kterou u cizího PR hledám. Když se **hlava PR rozejde se sha, proti které platí nálezy**, přibude
pod tím řádek s oběma — dokud se rovnají, je to trivia, jakmile se rozejdou, je to nejdůležitější
údaj na obrazovce, protože všechno pod ním mluví o kódu, který na větvi už není. Vpravo u záložek
je rozsah změny (`+X −Y`).

Detail PR má **záložky jako GitHub**: `Přehled` a `Změněné soubory`, podtržené, s odznakem
kolik je v přehledu k přečtení. Volba se pamatuje **u každého PR zvlášť** a otevírá se
`Přehled` — popis a diskuze se čtou dřív než kód, kterého se týkají.

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

**`Přehled`** dál nese to, co se neváže k žádnému řádku: popis PR od autora a pod ním konverzaci
chronologicky — review ostatních s odznakem (`schválil`, `vyžádal změny`), komentáře pod PR
a vlákna, jejichž řádek v aktuálním diffu není (typicky zastaralá po novém commitu). Ta se
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
plné šířky vejde. Počty `+X` a `−Y` jsou obarvené jako znak změny v samotném řádku — zeleně
a červeně, v souhrnu, v hlavičkách souborů i ve stromu souborů, takže „velký přírůstek“
a „velké mazání“ jsou poznat na první pohled.

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
a s odznakem, kolik je v souboru nálezů (červeným, když je mezi nimi blokující). V horní
liště je `Sbalit vše` / `Rozbalit vše` a skok na soubor nebo na nález sbalený soubor sám
otevře.

V mezerách mezi hunky jsou **šipky na rozbalení kontextu** — dotáhnou kód, který v diffu
není, po dvaceti řádcích nebo celý úsek naráz. Obsah souboru se čte z GitHubu až na
kliknutí; když se mezera rozbalí celá, hunky se slijí a hlavička mezi nimi zmizí.
`Zobrazit jen diff` sbalí všechno zpátky. **Kód kolem nálezu, jehož řádek v diffu není,
se dotáhne sám** — nález bez svého kódu se nedá posoudit. Nahoře v liště je **strom
souborů** pro skok kamkoli v diffu.

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

**Nálezy visí jako bubliny u řádků, kterých se týkají** — pill kategorie, verdict, jméno
revieweru a rozbalitelný scénář selhání; blokující nález má červený pruh. Shodu dvou
reviewerů na jednom místě označí `2×`, ale jejich texty se neslučují. Nález na řádek, který
v diffu není, se neztratí: visí u hlavičky souboru a nabídne ten řádek dotáhnout. Bubliny
jdou vypnout přepínačem nad diffem.

**Nálezy se procházejí šipkami v liště nad diffem** (#187): `2/3` a dvě šipky, klávesově
`⌥↓` a `⌥↑`, na další blokující `⌥⇧↓`. Do té doby vedla cesta k dalšímu nálezu vždycky přes
panel — najít ho v seznamu a kliknout — takže seznam musel být pořád vidět. Zúžení
`jen blokující` mění, kam šipky skáčou; **odmítnuté nálezy se přeskakují**, protože nález,
kterému nevěřím, není práce k projití. Puntík zezelená, teprve až jsi prošel **všechna** místa,
ne když skončíš na posledním; a nálezy bez místa v kódu se do počtu neplete — nedá se na ně
skočit, tak je nápověda počítá zvlášť, aby `3/3` netvrdilo hotovo nad PR, kde zbývají v panelu.

Pod diffem je **panel s taby**: nálezy jako karty, Průběh a Moje review. Panel je jediné místo, kde jsou vidět nálezy **bez místa
v kódu** — chybějící testy nebo poznámky k architektuře; kvůli nim samotné bubliny
nestačí. Je vidět v **obou** záložkách, protože nálezy, průběh i rozdělané review patří
k celému PR, ne k diffu. Klik kamkoli do karty odscrolluje diff (a přepne na něj, když jsi
v `Přehledu`) tak, aby nad nálezem zůstalo pár řádků kontextu, a bublinu na chvíli
zvýrazní. Výška panelu se táhne za horní hranu a pamatuje se.

**Nález je karta se závažností na hraně** (#175): červená blokuje, oranžová je běžný nález,
šedá odmítnutý — tatáž škála jako v řádku fronty, aby seznam a panel neříkaly o téže věci každý
něco jiného. Nahoře `blokuje · kategorie · reviewer`, pod tím shrnutí na tři řádky a dole místo
v kódu, ořezané **zepředu**, ať zůstane vidět jméno souboru a číslo řádku. Karta, na které stojí
procházení šipkami, má rámeček a popisek `tady jsi`, takže je z panelu i z lišty nad diffem
poznat totéž místo.

Do #175 to byla řaditelná tabulka. **Řazení podle sloupců se tím ztratilo, a je to vědomé:**
nálezů je typicky pod dvacet a `Policy` je řadí podle závažnosti, tedy tak, jak se mají číst;
zúžit je jde filtrem reviewerů a přepínačem `jen blokující`. Tabulka se při šířkách okna
nedala nasázet rozumně — kategorie, místo a shrnutí se praly o místo a odmítnutí muselo skončit
jako odznak u kategorie, protože nový sloupec neměl kam.

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

V tabu **Průběh** běží časová osa toho, co reviewer právě dělá — který soubor čte, co
hledá, jaký příkaz spustil. Skládá se nativně z eventů, ne přeposíláním textu, takže
aplikace nepotřebuje vestavěný terminál; když je potřeba se do session vrátit, zkopíruje
se `claude --resume <id>` jedním tlačítkem. Osa zůstane i po doběhnutí běhu.

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
v `Přehledu`. Odeslaná odpověď se ve vlákně objeví hned, bez čekání na další načtení, protože
ji GitHub v odpovědi celou vrací. **Odpověď se nepotvrzuje** dialogem jako review: je to jedna
věta v diskuzi, dá se smazat a potvrzování každé by z okna udělalo klikačku — tlačítko je
pojmenované, takže se to nestane omylem.

Dvě věci, které nejsou vidět, ale jsou v tom to podstatné: **když odeslání selže, rozepsaný
text zůstane** na místě a chyba pod polem řekne, co s ní jde udělat. A **prázdná odpověď se
neodešle** — GitHub ji totiž přijme, nic nevytvoří a vrátí úspěch, takže by okno hlásilo
odeslanou odpověď, která nikdy nevznikla. `Vyřešit` se navíc nabízí jen tam, kde na to GitHub
dává právo; jinde by tlačítko vždycky selhalo.

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

### Odeslání review

**Dvě kliknutí, dvě různá tlačítka.** `Odeslat review…` v tabu `Moje review` nic neodesílá —
otevře potvrzení, ve kterém je vidět **celý payload**: verdikt, tělo tak, jak je napsané,
a každý řádkový komentář i s tím, ke kterému řádku a ke které straně diffu patří. Teprve
tlačítko tam zavolá GitHub. Zavřít se dá kdykoli a draft tím zůstane netknutý.

Ochrana stojí právě na tom výpisu, ne na obřadu: **žádné opisování názvu repa** a **žádný
druhý dialog nad sheetem**. Obojí se za týden odklikává poslepu a oslabí to i to první
potvrzení. Co zůstává, je pojmenování akce — tlačítko se jmenuje
`Odeslat APPROVE pro owner/repo#123` — a to, že **není výchozí**: Enterem se nic neodešle.

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
takže je moje review hned vidět v `Přehledu`. Otevřené zůstane jen tehdy, když GitHub vrátí
stav, kterému aplikace nerozumí — tam je jediná zpráva ta, že se to má zkontrolovat ručně.
**Selhání draft nemaže**: chyba je vypsaná i s tím, co se s ní dá dělat, a dá se zkusit znovu.

Vlákna, jejichž řádek v aktuálním diffu **není** (typicky zastaralá po novém commitu), se
do kódu nekotví — jejich čísla platila pro starý head, takže by bublina sedla na cizí řádky.
Domov mají v záložce `Přehled` spolu s review ostatních a komentáři pod PR, a je u nich vidět
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
- [`docs/claude-cli.md`](docs/claude-cli.md) — ověřené chování `claude` CLI
- [`docs/github-review-api.md`](docs/github-review-api.md) — ověřené chování zápisového
  review API GitHubu; podklad pro odesílání review (M6)
- [CLAUDE.md](CLAUDE.md) — pravidla pro práci v tomto repu
- [`docs/architektura.md`](docs/architektura.md) — co který modul drží a co se u něj nemá
  rozbít
- [`docs/testovani.md`](docs/testovani.md) — co se u které oblasti testuje a proč zrovna to
- [`docs/stav.md`](docs/stav.md) — co je hotové a co zbývá

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

**Co nedoběhlo, se neztratí.** Když se aplikace zavře, ptá se — session se ukončením zabije
a nahlášené nálezy by byly pryč. Na pád aplikace nebo `kill` se ptát nedá, takže se nálezy
**dotáhnou z transcriptu**, který si `claude` vede na disku: běh se poznamená, jakmile nahlásí
id session, a po startu se z něj přečte, co stihl. Takový výsledek je v řádku `přerušeno`, ne
`timeout` ani `čisté` — nedoběhl, takže se z něj nesmí soudit, že je hotovo.

Nálezy jsou klíčované head commitem PR. Když přijdou nové commity, předchozí nálezy se
označí jako zastaralé — nezobrazují se proti kódu, který už neexistuje.

### Notifikace

Co přijde a co v tom bude:

| Kdy | Co uvidím |
|---|---|
| Nový PR ve frontě | `Nový PR k review — owner/repo#123` a název PR |
| PR, který jsem už reviewoval, se vrátil | `Znovu požádáno o review — owner/repo#123` a název PR |
| Víc nových PR naráz | Jeden souhrn: `4 nové PR k review` a tři z nich jménem plus `a 1 další` |
| Víc naráz, něco z toho znovu | `4 PR k review (1 znovu)` |
| Review našlo nálezy | `owner/repo#123` a `3 nálezy, z toho 1 blokující.` |
| Review je čisté | `Reviewer nenašel žádný nález.` |
| Review se nepovedlo | Důvod, se kterým se dá něco dělat — spadlá session, timeout bez nálezů, selhaná pracovní kopie |

**Jedna notifikace na pull request**, ne jedna na skill: reviewery jedou paralelně a tři
hlášky za jednu věc jsou tři vyrušení. Nový výsledek review přepíše ten starý, aby vedle
`3 nálezy` nezůstala viset stará hláška `nenašel žádný nález`. Notifikace o témž PR systém řadí
k sobě.

**Co se hlásí, se nastavuje** — záložka `Notifikace` v okně nastavení: hlavní vypínač a čtyři
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
| **Odesílání na GitHub** | Platí pro review i pro odpovědi do vláken. Ve výchozím stavu vypnuté a zapíná se v nastavení, globálně i per repo. Brána je jedno místo (`PublishScope`), na které se ptá publisher i okno — jinak by tlačítko slibovalo něco, na čem odeslání skončí. Proti omylu nechrání seznam rep, ale potvrzení s úplným výpisem payloadu a kontrola, že se posílá proti commitu, který jsi viděl. |
| **Notifikace** | Slévají se nad seznamem z jednoho tiku pollingu, ne přes vlastní čekací okno — tik dodá všechna nová PR naráz, takže se slévá právě to, co se stalo mezi dvěma tiky, a nepotřebuje to stav ani zdržení hlášky. Vypnout je jde po událostech; s vypnutým hlavním přepínačem se nežádá ani o systémové oprávnění, protože dialog za něco vypnutého je dialog za nic. |
| **Novinky v aplikaci** | Okno mluví o tom, co vyšlo na GitHubu, ne o spuštěném buildu — verze v bundlu tagy nikdy nesledovala, takže by tvrdila `0.1`. Značka je poslední **viděný tag** v předvolbách aplikace (stav aplikace, ne nastavení k editaci) a historie se drží v paměti do konce běhu: disková cache by dala offline režim, ale je to další store s vlastním úklidem. |
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
  Diff/                   parsování unified diffu na soubory, hunky a řádky + slití do dvojic pro pohled vedle sebe
  Health/                 dostupnost služeb pro stavový řádek: status pages, signály, monitor
  Markdown/               vykreslení Markdownu z GitHubu: bloky, inline HTML od botů
  Policy/                 čisté funkce: slučování zdrojů, řazení, stav řádku, odhad jazyka
  Publish/                jediná cesta ven: odeslání review, odpovědi do vláken a jejich vyřešení, brána z nastavení
  Review/                 spuštění session claude a překlad stream-json na nálezy
  Polling/                obnovování seznamu v intervalu, backoff, neaktuální data
  Store/                  AppStore — stav, který kreslí okno (stav v AppStore.swift, metody v AppStore+*.swift);
                          ReviewStore a ReviewDraftStore — nálezy a rozdělaná review na disku
  Syntax/                 obarvení kódu: jazyky, tokenizace, paleta
  Support/                sdílené drobnosti bez příslušnosti k modulu
  Views/                  SwiftUI obrazovky
    ReleaseNotes/         okno s novinkami — historie vydání a release notes vybrané verze
    Settings/             okno nastavení (⌘,) — globální hodnoty a nastavení per repo
  Assets.xcassets/        ikona aplikace (generovaná, viz bin/make-icon.swift)
Tests/                    unit testy — target PRismTests
  Models/                 testy modelů + pomocníci na Codable round-trip
  Environment/            testy Environment vrstvy + fakes
  Checkout/               testy klonování — proti fake runneru i skutečnému gitu
  Config/                 testy čtení, zápisu a slučování konfigurace
  Diff/                   testy parseru diffu proti skutečným výstupům gh pr diff
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
bin/copilot-review.sh     vyžádání Copilot review na PR
bin/setup-signing.sh      jednorázová příprava stálého podpisu (self-signed certifikát)
bin/make-icon.swift       vykreslí ikonu do asset catalogu (bez závislosti, přes ImageRenderer)
bin/icon-sources/         oficiální značky, ze kterých se ikona skládá
Info.plist                název aplikace, verze, minimální systém
PRism.entitlements        vypnutý App Sandbox
Signing.xcconfig          podpis: ad-hoc default + volitelný Signing.local.xcconfig
docs/architektura.md      podrobnosti po modulech
docs/testovani.md         co se u které oblasti testuje
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
