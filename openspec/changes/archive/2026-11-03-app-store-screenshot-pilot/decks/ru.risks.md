# ru deck — translation / back-translation / risks

Source: `ScreenshotFixture.swift` en-austin-1, 55 entries in file order → `ru.json`
`[{index,text,notes}]`, indices 1-based = fixture order (`shot-e01`…`shot-e55`).
Durations, ordering, and ordered category links are untouched (text-only adaptation).

## Method disclosure (single-family deviation)

Produced with a **single LLM family** playing translator → blind back-translator →
reviewer in sequence, not three independent families. Per task 6.1 this deviation
is recorded here, not silent: confidence below is self-adjudicated and the deck
still requires task 6.2 validation (totals, week conventions, leakage) and 6.5
clipping review before any capture. No paid native review is proposed.

## Locale conventions

- Variant: Russian anchored on Moscow (ru → RU / Europe/Moscow per design §3).
- **Food category name: `Еда`** (custom `shot-cat-food`; the seven starter names
  come from the shipped ru bundle — Работа, Хобби, Спорт, Образование, Отдых,
  Сон, Развлечения — not from this deck. `Еда` is the everyday word; `Питание`
  rejected as formal/register-wrong for an app category.)
- Formality: all 27 distinct texts are nominal phrases (no ты/вы choice). The
  single notes value uses a passive construction (`отправлена`, agreeing with
  feminine `очередь`) precisely to avoid the Russian speaker-gendered past tense
  — see risk R2. No pronoun/adjective agreement risks elsewhere.
- Exact-text pair equivalent: English `Coffee`/`coffee` (case distinction, indices
  14+37 / 23+53) → **`Кофе`/`кофе`** at the same indices (2×/2×, totals 3900/3300 s
  preserved). Round-trips to the identical distinction.

## Cultural substitutions (persona mapping)

| en (Austin) | ru (Moscow) | Rationale |
|---|---|---|
| Breakfast tacos | Сырники на завтрак | Syrniki = the iconic Russian home breakfast; fits the 45-min morning slot |
| Farmers market | Фермерский рынок | Direct; weekend-market hobby slot (50/55 min) |
| ACL festival | Пикник Афиши | Moscow's iconic outdoor music festival, same 90-min entertainment+hobby slot |
| Barton Springs swim | Заплыв в Серебряном бору | Serebryany Bor = Moscow's river-swimming spot, same 70/75-min sport slot |
| Tacos | Пельмени | Everyday Russian lunch/dinner; repeat preserved (10, 33) |
| BBQ | Шашлыки | Direct cultural equivalent for the 60-min grill slot |
| Lunch break | Перерыв на обед | Direct |
| Team lunch | Обед с командой | Direct |
| Grocery run | Закупка продуктов | Weekly stock-up; fits the long 55/65-min slots |
| Trail run | Пробежка в Битце | Bitsa park trails; place-name ellipsis like es-419 `Chapultepec` (65 min keeps run context) |
| Brunch | Поздний завтрак | Descriptive late-morning meal for the 10:00 slot; loanword `бранч` rejected as less everyday — see risk R1 |
| Inbox zero | Разбор почты | Inbox triage; 30-min work slot (loses the "zero" jargon, see verdict 22) |
| Code review | Проверка кода | Standard term (3 occurrences) |
| Design sync | Созвон по дизайну | `созвон` is THE Russian office word for a call meeting — same register note as es-419 `junta` |
| Football night | Футбольный вечер | Soccer sense; same 70/95-min sport+entertainment slot |
| Side project | Свой проект | Direct, personal-log register |
| Deep work | Глубокая работа | Standard Cal Newport translation (4 occurrences, Track-frame candidate) |
| Live music | Живой концерт | `концерт` fits the long 85–110-min slots better than generic `музыка` |
| Evening walk | Вечерняя прогулка | Direct (4 occurrences) |
| Morning run | Утренняя пробежка | Direct (4 occurrences + draft twin) |
| Shipped the offline queue (notes) | Офлайн-очередь отправлена | Passive to dodge speaker-gender morphology — see risk R2 |

## Back-translation check (27 distinct texts + notes)

Format: ru → blind EN back-translation → verdict. Length ratio vs EN source
(char counts, measured 2026-10-30).

| # | ru | Back-translation | Ratio | Verdict |
|---|---|---|---|---|
| 1 | Утренняя пробежка | Morning run | 1.55 | OK, meaning exact; length watch (4 occurrences + draft twin) |
| 2 | Сырники на завтрак | Syrniki (curd pancakes) for breakfast | 1.20 | OK, Moscow-specific, more vivid than source |
| 3 | Перерыв на обед | Lunch break | 1.36 | OK; mild watch (3 occurrences) |
| 4 | Спортзал | Gym | 2.67 | OK (short absolute length, 8 chars) |
| 5 | Фермерский рынок | Farmers' market | 1.14 | OK |
| 6 | Пикник Афиши | Afisha Picnic (music festival) | 1.00 | OK, proper noun, no translation needed; real-brand flag, see R3 |
| 7 | Чтение | Reading | 0.86 | OK, shorter than source |
| 8 | Заплыв в Серебряном бору | Swim at Serebryany Bor | 1.26 | OK, real-place flag, see R3 |
| 9 | Пельмени | Pelmeni (dumplings, lunch) | 1.60 | OK; length watch for Recents row (2 occurrences) |
| 10 | Живой концерт | Live concert | 1.30 | OK, boundary ratio (3 occurrences) |
| 11 | Глубокая работа | Deep work | 1.67 | OK, standard translation; length watch (4 occurrences, Track-frame candidate) |
| 12 | Вечерняя прогулка | Evening walk | 1.42 | OK; length watch (4 occurrences) |
| 13 | Кофе / кофе | Coffee / coffee | 0.67 | OK, exact-text pair preserved incl. case split |
| 14 | Проверка кода | Code review | 1.18 | OK, standard term (3 occurrences) |
| 15 | Йога | Yoga | 1.00 | OK (Cyrillic spelling, zero Latin chars — no verbatim issue) |
| 16 | Обед с командой | Team lunch | 1.50 | OK; length watch for Recents row |
| 17 | Закупка продуктов | Grocery stock-up | 1.55 | OK; length watch (2 occurrences) |
| 18 | Квартальное планирование…командой | Quarterly planning workshop…platform team | 0.98 | OK, long-name edge case preserved (49 chars, still the longest deck text) |
| 19 | Футбольный вечер | Football (soccer) night | 1.14 | OK |
| 20 | Поздний завтрак | Late breakfast (brunch) | 2.50 | OK, descriptive equivalent; top length watch, see R1 |
| 21 | Свой проект | Own/side project | 0.92 | OK, shorter than source (2 occurrences) |
| 22 | Разбор почты | Clearing the inbox | 1.20 | OK; methodology jargon naturalized ("zero" not literal) |
| 23 | Пробежка в Битце | Run in Bitsa (park) | 1.78 | OK, place-name ellipsis; duration (65 min) keeps run context; see R3 |
| 24 | Созвон по дизайну | Design call/sync | 1.55 | OK; `созвон` is the correct RU office register |
| 25 | Киновечер | Movie night | 0.82 | OK, shorter than source |
| 26 | Шашлыки | Shashlik (BBQ skewers) | 2.33 | OK (short absolute length, 7 chars); no shorter faithful option |
| 27 | Офлайн-очередь отправлена (notes) | The offline queue has shipped | 1.00 | OK; passive verified as gender-neutral (see R2) |

No English text or notes verbatim in the deck: machine scan of all 55 text values
+ the notes value finds zero `[A-Za-z]` characters and zero matches against the
28 distinct EN source strings (keys `index`/`text`/`notes` are schema, not user
copy).

Duration plausibility (spot check against fixture slots): 90 мин Пикник Афиши ✓ ·
70/75 мин Заплыв в Серебряном бору ✓ · 60 мин Шашлыки ✓ · 50/55 мин Фермерский
рынок ✓ · 55/65 мин Закупка продуктов ✓ · 70/95 мин Футбольный вечер ✓ · 90 мин
Киновечер ✓ · 85–110 мин Живой концерт ✓ · 100–120 мин Глубокая работа ✓ ·
25–35 мин Кофе/кофе ✓ (matches EN short-break slots) · 65 мин Пробежка в Битце ✓ ·
45 мин Поздний завтрак at the 10:00 slot ✓ · 40/60 мин Пельмени ✓.

Identical EN texts map to identical RU texts throughout (verified: Утренняя
пробежка×4, Перерыв на обед×3, Спортзал×2, Фермерский рынок×2, Чтение×4, Заплыв в
Серебряном бору×2, Пельмени×2, Живой концерт×3, Глубокая работа×4, Вечерняя
прогулка×4, Кофе×2, кофе×2, Проверка кода×3, Йога×2, Закупка продуктов×2,
Футбольный вечер×2, Свой проект×2 — same grouping shape as EN).

## Risk list / sign-off

1. **Length watches (6.5 input):** `Поздний завтрак` (2.50×, the top watch —
   descriptive phrase for a 6-char source; `Бранч` would be compact but is less
   everyday Moscow usage), `Пробежка в Битце` (1.78×), `Глубокая работа`
   (1.67×, 4× + Track-frame candidate), `Пельмени` (1.60×, 2×), `Закупка
   продуктов` (1.55×, 2×), `Созвон по дизайну` (1.55×), `Утренняя пробежка`
   (1.55×, 4× + draft twin), `Обед с командой` (1.50×), `Вечерняя прогулка`
   (1.42×, 4×), `Перерыв на обед` (1.36×, 3×), `Живой концерт` (1.30× boundary,
   3×). All are the faithful standard terms; none was shortened into unnatural
   phrasing to game the ratio. (`Спортзал` 2.67× and `Шашлыки` 2.33× are short
   absolute lengths — no action.) Must be cleared by the Recents/History/Insights
   fit review (task 6.5) — not by further blind shortening here. Russian is a
   priority review locale alongside Spanish/Portuguese per the spec's clipping
   requirement.
2. **Speaker-gender morphology (notes):** Russian past tense marks speaker gender
   (`Сдал` masc / `Сдала` fem), unlike EN/ES/PT/ZH. The deck deliberately uses
   the passive `Офлайн-очередь отправлена` (agrees with feminine `очередь`, says
   nothing about the speaker) so the fixture persona stays gender-neutral. Do NOT
   "improve" it to `Залил`/`Сдал` slang without reopening this risk.
3. **Real place/brand names:** `Пикник Афиши` (real festival brand), `Серебряный
   бор`, `Битца` (real Moscow places) — plausible fiction consistent with the
   es-419 (`Vive Latino`, `Chapultepec`) and pt-BR (`Virada Cultural`, `Sesc`)
   precedents. Generics (`Фестиваль`, `Купание в реке`, `Пробежка в парке`) are
   drop-in alternatives if the owner wants zero real names. Low risk.
4. **Single-family adjudication** (see Method disclosure): confidence is
   self-reported (high on everyday items, medium on `Созвон` register and the
   passive notes construction). A second-family spot-check of at most the length-
   watch items would close this cheaply; full re-translation is not warranted.
5. **Running draft twin:** English draft `Morning run` duplicates entry text;
   the ru draft MUST be `Утренняя пробежка` to preserve the twin relationship
   (owner of the fixture-side change to confirm; not part of this JSON).
6. **Add-entry sample** (`Deep work` / `Shipped the offline queue`) MUST become
   `Глубокая работа` / `Офлайн-очередь отправлена` for deck consistency.
7. **Totals invariance:** text-only change — durations/order/categories untouched,
   so `expected_totals.json` (27 texts, 198600 s, per-text seconds) holds
   provided the validator maps by index, not by string match. Task 6.2 to confirm
   no validator keys on English literals. Locale pin ru → RU / Europe/Moscow;
   week membership and expected totals MUST be recomputed under locale-native
   week rules at preparation time; this deck does not pin totals.

Sign-off: deck structurally valid (55/55, 27 distinct, pair + notes + long-name
edge cases at correct indices); **NOT approved for capture** — pending 5.4
English gate, 6.2 validation, and 6.5 clipping review.
