# zh-Hans 上海 deck — back-translation check & risk report

- Locale `zh-Hans`, region 上海, timezone `Asia/Shanghai`.
- Source: `ios/TimeOfLife/TimeOfLife/Core/Capture/ScreenshotFixture.swift`, entries in fixture order (index 1–55 = `entries[0..54]`). Durations, ordering, and ordered category relationships unchanged — text/notes only.
- Method: single-session translate → blind re-read of candidates as back-translation → adjudication. DEVIATION: translator, back-translator, and reviewer are one model family (no paid native review, same limitation as the earlier locale pass). Residual tone risk transfers to author sign-off.
- Formality: neutral. Entry texts are noun/verb phrases with no pronouns, so 你/您 is N/A. Notes sample is statement-style, no honorifics.
- No-English rule: no entry text or notes reuses an English source verbatim; machine scan of the JSON values finds zero `[A-Za-z]` characters (keys `index/text/notes` are schema, not user copy).

## Required edge cases (timeline contract)

- Exact-text distinction: EN `Coffee` (idx 14, 37) vs `coffee` (idx 23, 53) → ZH `喝咖啡` vs `咖啡`. Equivalent minimal pair: presence/absence of one character 喝, both natural for a coffee break, visually distinct in Recents exactly like the EN case pair.
- Multi-category entries: idx 7 草莓音乐节 (entertainment+hobby), idx 21/47 足球之夜 (sport+entertainment) — both read naturally under either category.
- Notes-bearing entry: idx 22 深度工作 + `离线队列已上线` (one notes glyph, as in EN).
- Long name: idx 20 `和平台团队的季度规划研讨会` (13 CJK chars vs EN 48 — stays the longest deck text, no truncation risk).
- Distinct texts: 27 (>12 required); Recents cap exercised the same way as EN.
- Food category name: 美食 (custom `shot-cat-food`; starter names come from the shipped zh-Hans bundle per the capture design, not from this deck).

## Adjudication table (distinct texts; lengths = EN chars / ZH chars)

| EN source | ZH candidate | Back-translation | Verdict | Len |
|---|---|---|---|---|
| Morning run | 晨跑 | morning run | accept | 11/2 |
| Breakfast tacos | 生煎包 | shengjian buns | accept, adapted (Shanghai breakfast) | 14/3 |
| Lunch break | 午餐休息 | lunch break | accept | 11/4 |
| Gym | 健身 | gym workout | accept | 3/2 |
| Farmers market | 逛菜市场 | trip to the wet market | accept | 14/4 |
| ACL festival | 草莓音乐节 | strawberry music festival | accept, adapted (see R1) | 12/5 |
| Reading | 读书 | reading | accept | 7/2 |
| Barton Springs swim | 游泳馆游泳 | swimming at the pool | accept, adapted (see R2) | 19/5 |
| Tacos | 牛肉面 | beef noodles | accept, adapted (see R3) | 5/3 |
| Live music | 现场演出 | live show | accept | 10/4 |
| Deep work | 深度工作 | deep work | accept | 9/4 |
| Evening walk | 滨江散步 | riverside walk | accept, adapted (see R4) | 12/4 |
| Coffee | 喝咖啡 | have coffee | accept, pair A | 6/3 |
| coffee | 咖啡 | coffee | accept, pair B | 6/2 |
| Code review | 代码评审 | code review | accept | 11/4 |
| Yoga | 瑜伽 | yoga | accept | 4/2 |
| Team lunch | 团队午餐 | team lunch | accept | 10/4 |
| Grocery run | 超市采购 | grocery shopping | accept | 11/4 |
| Quarterly planning workshop with the platform team | 和平台团队的季度规划研讨会 | quarterly planning workshop with the platform team | accept, long-text preserved | 48/13 |
| Football night | 足球之夜 | football night | accept | 14/4 |
| Brunch | 早午餐 | brunch | accept | 6/3 |
| Side project | 个人小项目 | personal side project | accept | 12/5 |
| Inbox zero | 清空收件箱 | clear the inbox | accept | 10/5 |
| Trail run | 世纪公园跑步 | run at Century Park | accept, adapted (see R5) | 9/6 |
| Design sync | 设计同步会 | design sync | accept | 11/5 |
| Movie night | 电影之夜 | movie night | accept | 10/4 |
| BBQ | 户外烧烤 | outdoor barbecue | accept | 3/4 |
| Shipped the offline queue (notes) | 离线队列已上线 | the offline queue has shipped | accept | 24/7 |

Length gate: every ZH candidate is ≤13 chars and shorter than its EN source — no 1.3× overflow, no tight-surface truncation risk (Recents, History header, Insights footnote).

## Index → text map (fixture order)

1 晨跑 · 2 生煎包 · 3 晨跑 · 4 午餐休息 · 5 健身 · 6 逛菜市场 · 7 草莓音乐节 · 8 读书 · 9 游泳馆游泳 · 10 牛肉面 · 11 现场演出 · 12 深度工作 · 13 滨江散步 · 14 喝咖啡 · 15 代码评审 · 16 读书 · 17 瑜伽 · 18 团队午餐 · 19 超市采购 · 20 和平台团队的季度规划研讨会 · 21 足球之夜 · 22 深度工作 (+notes 离线队列已上线) · 23 咖啡 · 24 早午餐 · 25 个人小项目 · 26 清空收件箱 · 27 世纪公园跑步 · 28 午餐休息 · 29 现场演出 · 30 设计同步会 · 31 电影之夜 · 32 晨跑 · 33 牛肉面 · 34 健身 · 35 深度工作 · 36 读书 · 37 喝咖啡 · 38 代码评审 · 39 滨江散步 · 40 瑜伽 · 41 午餐休息 · 42 逛菜市场 · 43 个人小项目 · 44 读书 · 45 游泳馆游泳 · 46 户外烧烤 · 47 足球之夜 · 48 深度工作 · 49 滨江散步 · 50 晨跑 · 51 超市采购 · 52 现场演出 · 53 咖啡 · 54 代码评审 · 55 滨江散步

Identical EN texts map to identical ZH texts throughout (verified: 晨跑×4, 午餐休息×3, 健身×2, 逛菜市场×2, 读书×4, 游泳馆游泳×2, 牛肉面×2, 现场演出×3, 深度工作×4, 滨江散步×4, 喝咖啡×2, 咖啡×2, 代码评审×3, 瑜伽×2, 超市采购×2, 足球之夜×2, 个人小项目×2).

## Duration plausibility (spot check)

90 分钟 草莓音乐节 ✓ · 70/75 分钟 游泳馆游泳 ✓ · 60 分钟 户外烧烤 ✓ · 50/55 分钟 逛菜市场 ✓ · 55/65 分钟 超市采购 ✓ · 70/95 分钟 足球之夜 ✓ · 90 分钟 电影之夜 ✓ · 85–110 分钟 现场演出 ✓ · 120 分钟 深度工作 ✓ · 25–45 分钟 咖啡/喝咖啡 ✓ (matches EN short-break slots).

## Risks

- R1 草莓音乐节 is a real event brand running a Shanghai edition — fine as fictional personal data, but the owner may prefer a generic 音乐节. Low risk.
- R2 游泳馆游泳 drops the Barton Springs proper noun deliberately (Austin-only reference). No Shanghai pool named; generic is safer. Low risk.
- R3 牛肉面 carries a northwestern association; everyday Shanghai lunch nonetheless. Alternative: 盖浇饭. Low risk.
- R4 滨江散步 leans Huangpu-riverside imagery; reads generic-city in context. Low risk.
- R5 世纪公园跑步 names a real Shanghai park as the trail-run anchor — plausible fiction, flag if owner wants no real place names. Low risk.
- R6 Single-family adjudication (see deviation above) — residual tone risk open until author sign-off.
- R7 美食 vs alternatives 餐饮/饮食: 美食 chosen as the most app-category-natural; confirm against the shipped zh-Hans starter tone at integration.

## Sign-off

Mechanical checks green (55 entries, indices 1–55, identical-group consistency, zero Latin characters in values, 27 distinct texts, durations untouched in the fixture). Content approval pending owner review — this report is evidence, not approval.
