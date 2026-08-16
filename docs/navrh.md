# Vizuální návrh (mockup)

Jak se pracuje s mockupem: kde je, čím se čte, jak se aktualizuje a co znamená „zapracovat
do návrhu“. Pravidlo samotné — **co se musí nakreslit a odsouhlasit dřív, než na to vznikne
issue** — je v [`CLAUDE.md`](../CLAUDE.md), sekce *Návrh (mockup)*.

## Kde návrh je

**Artifact `PRism — návrh vizuální revize`:**
<https://claude.ai/code/artifact/5206622c-19b2-4c4e-9041-849d5b6d4a51>

Je to jedna HTML stránka: tokeny v `:root` a pod nimi devatenáct sekcí. Většina kreslí jednu
obrazovku nebo jeden stav v rámu okna (`.win`) a vedle sebe má poznámky (`.notes`), proč je to
tak; zbytek rozhodnutí vysvětluje — *Dvanáct stavů, které se nesmí slít*, *Kde jsem si vybral,
a co to stálo*, *Co by se muselo přepsat*.

**Poslední sekce nemusí být poslední obrazovka.** Sekce 19 (*Review — Commity*) kreslí tab,
který v okně sedí třetí zleva; přečíslovat kvůli němu osmnáct sekcí by rozbilo odkazy, které
na ně míří. Pořadí sekcí je tedy pořadí, ve kterém vznikly, ne pořadí v UI.

**V repu ten soubor není a nemá být.** Návrh je živý dokument, který se překresluje častěji než
kód; kdyby ležel v repu, byl by z každé úpravy návrhu commit, review a merge. Cena za to je, že
adresa musí být zapsaná — proto tenhle soubor.

Adresa se dá dohledat i bez něj: nástroj `Artifact` s `action: "list"` vypíše artifacty
uživatele i s adresami.

## Jak se z něj čte

**`WebFetch` na tu adresu, ne `curl`.** Artifacty jsou soukromé a `curl` na nich dostane buď
skořápku aplikace, nebo 403; `WebFetch` je přečte přes přihlášení k claude.ai. Celý dokument se
u toho uloží na disk a v odpovědi přijde cesta k němu — a **teprve v tom souboru se grepuje**.
Stránka má přes 200 kB, takže odpověď modelu je vždycky výtah; hodnota, podle které se pak
kreslí (poloměr, mezera, barva), se musí přečíst v CSS doslova.

```bash
# ze staženého souboru, ne z výtahu
grep -n "inline-find" -A 20 <cesta-k-uloženému-html>
```

**Tokeny v `:root` jsou `App/Views/Palette.swift`.** `--bg`, `--panel`, `--line`, `--ink`,
`--accent`, `--crit`, `--find` a spol. sedí na `Palette` jedna ku jedné včetně obou motivů
(`#F4F6FA`/`#080A0F` = `Palette.background`, `#5B47E0`/`#8B7CFF` = `Palette.accent`). Když se
mění barva, mění se **obojí** — jinak se paleta a návrh rozejdou a další srovnání bude tvrdit,
že chybu má aplikace.

Rozměry z CSS se berou jako body 1 : 1 (`font-size: 11.5px` → `.font(.system(size: 11.5))`,
`border-radius: 6px` → `cornerRadius: 6`). Není to samozřejmost, je to zvyklost tohohle repa —
dodržuje ji dnešní kód a odchylka od ní musí být zapsaná jako rozhodnutí.

## Jak se aktualizuje

Napsat HTML do souboru a publikovat nástrojem `Artifact` **s `url` té existující stránky**.
Bez `url` vznikne druhý artifact — a dva návrhy jsou horší než žádný, protože se nedá poznat,
který platí.

1. Přečíst současný obsah (`WebFetch`), uložený soubor vzít jako výchozí bod.
2. Upravit ho — sekci, které se to týká; novou obrazovku přidat jako další sekci **i s poznámkami**
   (`.notes`), protože návrh bez důvodů se za měsíc nedá obhájit ani změnit.
3. Publikovat: `Artifact` s `file_path` a `url: "https://claude.ai/code/artifact/5206622c-…"`.
   Titulek a favicon zůstávají — mění se obsah, ne identita stránky.

Nové obrazovky se kreslí **stejnými třídami jako zbytek** (`.win`, `.card`, `.pill`, `.mini`, …).
Vlastní styl pro jednu sekci znamená, že se návrh přestal skládat z jednoho systému, a to je
přesně to, čemu má mockup bránit.

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

Stejně jako dřív: **obrázek vedle obrázku**, ne čtení kódu. Sekce se vyřízne do samostatného
souboru (stránka je dlouhá a `--screenshot` bere jen viewport) a vyrenderuje headless Chromem;
postup i s příkazem je v [`docs/testovani.md`](testovani.md), sekce o kontrole vzhledu.

U #181 to našlo čtyři odchylky, které kontrolou kódu prošly — pevnou šířku sloupce místo poměru
`1.45fr 1fr`, chybějící popisky v hlavičkách bloků, chybějící blok `Co teď` a odsazený proužek
řádku. U #216 to našlo uzel osy o 16 bodech místo 24. Zpaměti se to nepozná.
