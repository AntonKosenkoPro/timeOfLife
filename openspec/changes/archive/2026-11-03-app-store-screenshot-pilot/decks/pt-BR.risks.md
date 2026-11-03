# pt-BR (São Paulo) deck — back-translation check & risk report

Status: **DRAFT**. Pending English pilot owner approval (task 5.4); this deck MUST NOT
gate any capture before that gate clears. No code, no fixture edits, no commits.

## Contract

- Source: `ios/TimeOfLife/TimeOfLife/Core/Capture/ScreenshotFixture.swift`
  (`en-austin-1`, 55 entries, daysAgo 0–20, entry order = array order).
- Deck file: `decks/pt-BR.json`, `[{index, text, notes}]`, index 1-based = fixture
  array position (index N = `shot-eNN`). Verified: 55 entries, indices 1–55,
  27 distinct texts (same count/grouping as English), zero English-verbatim strings.
- Durations, timeline shape, day placement, and ordered category links are
  UNTOUCHED — text/notes adaptation only. Multi-category entries (7, 21, 47),
  notes-bearing entry (22), long name (20), and exact-text pair positions
  (14/37 vs 23/53) sit at the same indices as the English deck.
- Locale pin (design §3): pt-BR → BR / America/Sao_Paulo. Week membership and
  expected totals MUST be recomputed under locale-native week rules at
  preparation time; this deck does not pin totals.
- Food category name (custom, no shipped seed string): **Comida**.
  Other categories reuse shipped pt-BR seeds: Trabalho, Hobby, Esporte, Estudo,
  Descanso, Sono, Entretenimento.

## Persona mapping (Austin → São Paulo)

| EN source | pt-BR | Rationale |
|---|---|---|
| Morning run | Corrida matinal | Direct; Ibirapuera-park-jogger persona |
| Breakfast tacos | Tapioca na padaria | Padaria breakfast; tapioca = Brazilian morning staple |
| Lunch break | Pausa para o almoço | Direct |
| Gym | Academia | Standard pt-BR usage |
| Farmers market | Feira livre | The exact São Paulo institution |
| ACL festival | Virada Cultural | São Paulo's iconic 24h music festival (entertainment) |
| Reading | Leitura | Direct |
| Barton Springs swim | Natação no Sesc | Sesc pools = São Paulo public-swimming institution (sport) |
| Tacos | Pastel | Iconic São Paulo street food; repeat preserved (10, 33) |
| Live music | Música ao vivo | Direct |
| Deep work | Trabalho profundo | Direct |
| Evening walk | Caminhada noturna | Direct |
| Coffee / coffee | Café / café | Exact-text pair equivalent (case distinction preserved, same indices) |
| Code review | Revisão de código | Direct |
| Yoga | Ioga | Volp spelling; avoids English-verbatim "Yoga" (see risk R3) |
| Team lunch | Almoço em equipe | Direct |
| Grocery run | Compras no mercado | Direct |
| Quarterly planning workshop… | Workshop de planejamento trimestral com o time da plataforma | Long name preserved (60 chars vs EN 50 — see risk R1) |
| Football night | Noite de futebol | Soccer; paulistano weeknight |
| Brunch | Brunch de domingo | Loanword is standard São Paulo usage; full string ≠ EN verbatim |
| Side project | Projeto pessoal | Direct |
| Inbox zero | Caixa de entrada zerada | Methodology name naturalized |
| Trail run | Corrida na trilha | Cantareira/Carmo trail persona |
| Design sync | Alinhamento de design | Direct |
| Movie night | Noite de cinema | Direct |
| BBQ | Churrasco | Direct cultural equivalent |
| Notes: "Shipped the offline queue" | "Subi a fila offline" | pt-BR dev slang for "shipped" |

## Back-translation check (pt-BR → EN, meaning preserved?)

| pt-BR | Back-translation | Verdict |
|---|---|---|
| Corrida matinal | Morning run | ✓ |
| Tapioca na padaria | Tapioca at the bakery (breakfast) | ✓ context kept |
| Pausa para o almoço | Lunch break | ✓ |
| Academia | Gym | ✓ (in log context; see R4) |
| Feira livre | Open-air farmers' market | ✓ |
| Virada Cultural | All-night culture/music festival | ✓ entertainment slot |
| Leitura | Reading | ✓ |
| Natação no Sesc | Swimming at Sesc | ✓ sport slot |
| Pastel | Pastel (fried pastry, lunch) | ✓ food slot (see R4) |
| Música ao vivo | Live music | ✓ |
| Trabalho profundo | Deep work | ✓ |
| Caminhada noturna | Evening/night walk | ✓ |
| Café / café | Coffee / coffee | ✓ pair equivalent |
| Revisão de código | Code review | ✓ |
| Ioga | Yoga | ✓ |
| Almoço em equipe | Team lunch | ✓ |
| Compras no mercado | Grocery shopping | ✓ |
| Workshop de planejamento trimestral com o time da plataforma | Quarterly planning workshop with the platform team | ✓ long |
| Noite de futebol | Football (soccer) night | ✓ |
| Brunch de domingo | Sunday brunch | ✓ |
| Projeto pessoal | Side project | ✓ |
| Caixa de entrada zerada | Inbox zero | ✓ |
| Corrida na trilha | Trail run | ✓ |
| Alinhamento de design | Design sync | ✓ |
| Noite de cinema | Movie night | ✓ |
| Churrasco | BBQ | ✓ |
| Subi a fila offline | Shipped the offline queue | ✓ |

Machine checks (2026-10-30): JSON parses; 55/55 indices; keys exactly
`{index,text,notes}`; 0 English-verbatim text/notes strings against the 28
distinct EN source strings; `Café` at 14/37 and `café` at 23/53 (same slots as
EN `Coffee`/`coffee`); single notes value at index 22; long name at index 20.

## Risks & sign-off

- **R1 (clipping — HIGH, expected):** the workshop name is 60 chars (EN: 50,
  +20%). Portuguese is the priority review locale per spec ("Final frames pass
  visual and language review"). Must be inspected in Recents (fixed height),
  History headers, Insights footnote, and Add-entry cards at task 6.5; reject
  and re-scope on truncation, never image-edit.
- **R2 (method):** LLM-only single-pass adaptation with machine back-translation
  check; no paid native review (allowed by task 6.1). Cross-family adjudication
  is this report only — recorded here, not silently skipped.
- **R3 (Ioga spelling):** "Ioga" chosen over the common typed form "Yoga" to
  satisfy the no-English-verbatim rule. Residual risk: a real user would more
  likely type "Yoga". Accepted as fixture-only wording; flag if owner prefers
  authenticity over the verbatim rule.
- **R4 (ambiguity):** "Academia" also means "academy"; "Pastel" is also an
  adjective ("pastel color"). Both are unambiguous in a food/sport activity-log
  context; back-translation confirms slot meaning.
- **R5 (loanword):** "Brunch de domingo" keeps "brunch" — standard in São Paulo
  usage and not a verbatim EN entry. No action unless owner objects.
- **R6 (totals):** pt-BR week rules/totals are NOT pinned here; preparation must
  compute expected totals under America/Sao_Paulo locale-native rules and fail
  closed on mismatch (spec: "Equivalent localized decks").
- **Sign-off:** draft by LLM lane, machine-verified as above. Human/owner
  acceptance happens at task 6.6 presentation, only after the 5.4 English pilot
  gate. No foreign-language leakage: all 55 texts + 1 notes string are pt-BR.
