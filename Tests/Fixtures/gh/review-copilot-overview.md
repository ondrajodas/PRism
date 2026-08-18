## Pull request overview

PR řeší issue #375: odstraňuje poslední výskyt zakázaného vzoru „pružná výška v řádku líného seznamu“ v ose konverzace tím, že svislou linku kreslí jako `background` uzlu místo samostatného prvku s `frame(maxHeight: .infinity)`. Současně rozšiřuje a zpřesňuje sondy výkonu a vzhledu tak, aby skutečně měřily/rendrovaly relevantní obsah (včetně načtené konverzace) a pokrývaly všechny taby detailu.

**Changes:**
- `ConversationNodeView` kreslí osu (linku) jako pozadí uzlu a zavádí pevné minimum výšky pro nejkratší uzly.
- `IdleDiffSpinProbe` doplňuje scénáře pro konverzaci, ostatní taby a měření „projíždění“ (scrolling) pro konverzaci i diff.
- `DetailTabRenderProbe` nově načítá konverzaci z fixture, aby render tabu „Konverzace“ nebyl jen spinner; dokumentace a specifikace k tomu přidávají záznam rozhodnutí a postupy spuštění sond.

### Reviewed changes

Copilot reviewed 8 out of 8 changed files in this pull request and generated no comments.

<details>
<summary>Show a summary per file</summary>

| File | Description |
| ---- | ----------- |
| App/Views/ConversationNodeView.swift | Překreslení svislé osy konverzace na `background` a odstranění pružné výšky v řádku líného seznamu. |
| Tests/Views/IdleDiffSpinProbe.swift | Rozšíření výkonové sondy o další taby a měření scrollování (konverzace + diff); doplnění commitů a checků do storu pro realistický obsah. |
| Tests/Views/DetailTabRenderProbe.swift | Načtení konverzace z fixture pro správný render tabu „Konverzace“ a smysluplné porovnání vzhledu. |
| docs/testovani.md | Doplnění výsledků měření a přesného postupu spuštění sond (`-only-testing` se závorkami, `grep -a`). |
| docs/architektura.md | Upřesnění pravidla k `maxHeight: .infinity` (výška ≠ šířka) a vyjmenování ohraničených forem; aktualizace popisu `ConversationNodeView`. |
| docs/stav.md | Záznam, že #375 je hygiena/pokrytí, nikoli oprava ztuhnutí; shrnutí ověření a pastí sond. |
| docs/superpowers/specs/2026-07-31-prism-design.md | Záznam rozhodnutí k #375 (motivace, zamítnuté alternativy, důvody). |
| CLAUDE.md | Aktualizace pravidla/poznámek k pružné výšce v líném seznamu a k tomu, jak ji kontrolovat. |
</details>








---

💡 <a href="/ondrajodas/PRism/new/main?filename=.github/skills/code-review/SKILL.md" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Add a `code-review` agent skill</a> or configure MCP servers for context-aware, tailored reviews. <a href="https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/use-code-review#mcp-servers-and-agent-skills" class="Link--inTextBlock" target="_blank" rel="noopener noreferrer">Learn more in the docs.</a>
