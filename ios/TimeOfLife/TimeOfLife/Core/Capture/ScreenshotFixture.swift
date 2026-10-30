// swiftlint:disable file_length
#if SCREENSHOT_CAPTURE
import Foundation

/// The versioned Austin timeline with five localized decks
/// (screenshot-capture design §2).
///
/// 55 committed entries over 21 days ending on the pinned reference Tuesday,
/// plus a separate running draft. Durations, ordering, and ordered category
/// relationships are the shared timeline contract: localized decks adapt
/// entry text/notes (and the custom Food category name) only. Every entry
/// completes before the logical reference; the draft never contributes to
/// totals. Sources: `openspec/changes/app-store-screenshot-pilot/decks/`
/// (`ru`/`es-419`/`pt-BR` bare arrays, `zh-Hans` metadata+entries split).
///
/// This file is `#if SCREENSHOT_CAPTURE`: fixture data never compiles into
/// shipping builds (tasks 2.4).
enum ScreenshotFixture {
    static let deckVersion = ScreenshotCaptureRequest.enAustinDeckVersion
    static let entryCount = 55

    // MARK: - Categories (stable IDs, canonical order)

    static let workID = "shot-cat-work"
    static let hobbyID = "shot-cat-hobby"
    static let sportID = "shot-cat-sport"
    static let educationID = "shot-cat-education"
    static let relaxID = "shot-cat-relax"
    static let sleepID = "shot-cat-sleep"
    static let entertainmentID = "shot-cat-entertainment"
    static let foodID = "shot-cat-food"

    /// Supported request locale identifiers (design §3 locale pins).
    static let supportedLocaleIdentifiers = ["en", "ru", "zh-Hans", "es-419", "pt-BR"]

    static func isSupportedLocale(_ localeIdentifier: String) -> Bool {
        supportedLocaleIdentifiers.contains(localeIdentifier)
    }

    /// Custom Food category name per deck (risks reports): en Food,
    /// ru Еда, zh 美食, es Comida, pt Comida. Unknown locales fall back
    /// to the English name (fail-closed request validation never reaches
    /// here with an unsupported locale).
    static func foodName(for localeIdentifier: String) -> String {
        switch localeIdentifier {
        case "ru": return "Еда"
        case "zh-Hans": return "美食"
        case "es-419": return "Comida"
        case "pt-BR": return "Comida"
        default: return "Food"
        }
    }

    /// Starter names come from the shipped bundles (risks reports), not
    /// from the deck JSON — pinned here so the isolated capture store
    /// seeds the same names the localized UI displays.
    private static func starterNames(for localeIdentifier: String) -> [String] {
        // Order: work, hobby, sport, education, relax, sleep, entertainment.
        switch localeIdentifier {
        case "ru":
            return ["Работа", "Хобби", "Спорт", "Образование", "Отдых", "Сон", "Развлечения"]
        case "zh-Hans":
            return ["工作", "爱好", "运动", "学习", "休闲", "睡眠", "娱乐"]
        case "es-419":
            return ["Trabajo", "Pasatiempo", "Deporte", "Estudio", "Descanso", "Sueño", "Entretenimiento"]
        case "pt-BR":
            return ["Trabalho", "Hobby", "Esporte", "Estudo", "Descanso", "Sono", "Entretenimento"]
        default:
            return ["Work", "Hobby", "Sport", "Education", "Relax", "Sleep", "Entertainment"]
        }
    }

    /// Localized categories in `LocalStore.starterCategoryIcons` order,
    /// plus the custom Food category appended after the starters.
    static func categories(for localeIdentifier: String, stamp: Date) -> [Category] {
        let starters = starterNames(for: localeIdentifier)
        let rows: [(String, String, String)] = [
            (workID, starters[0], "briefcase"),
            (hobbyID, starters[1], "paintbrush"),
            (sportID, starters[2], "figure.run"),
            (educationID, starters[3], "book"),
            (relaxID, starters[4], "cup.and.saucer"),
            (sleepID, starters[5], "bed.double"),
            (entertainmentID, starters[6], "tv"),
            (foodID, foodName(for: localeIdentifier), "fork.knife"),
        ]
        return rows.map { Category(id: $0.0, name: $0.1, icon: $0.2, createdAt: stamp, updatedAt: stamp) }
    }

    /// English starter names in `LocalStore.starterCategoryIcons` order,
    /// plus the custom Food category appended after the starters.
    static func categories(stamp: Date) -> [Category] {
        categories(for: "en", stamp: stamp)
    }

    // MARK: - Running draft (separate intent, never committed)

    /// Draft twin per deck (risks reports): duplicates entry index 1 so
    /// the Track running frame mirrors a committed text in every locale.
    static func draftText(for localeIdentifier: String) -> String {
        switch localeIdentifier {
        case "ru": return "Утренняя пробежка"
        case "zh-Hans": return "晨跑"
        case "es-419": return "Carrera matutina"
        case "pt-BR": return "Corrida matinal"
        default: return "Morning run"
        }
    }

    static let draftText = "Morning run"
    static let draftCategoryIDs = [sportID]
    static let draftNotes = ""

    static func draftCategoryIDs(for _: String) -> [String] { [sportID] }
    static func draftNotes(for _: String) -> String { "" }

    /// Every locale's draft text (activity cleanup matches capture-owned
    /// activities from any deck, never another account's).
    static var allDraftTexts: [String] {
        supportedLocaleIdentifiers.map { draftText(for: $0) }
    }

    // MARK: - Add-entry frame sample (Log Time sheet draft, never saved)

    /// Sample content for the Add-entry frame (screenshot-capture spec):
    /// the real Log Time sheet opens with these draft values. Committed
    /// fixture data is untouched — totals stay identical (55 entries).
    /// Localized per deck for deck consistency (risks reports).
    static func addEntryText(for localeIdentifier: String) -> String {
        switch localeIdentifier {
        case "ru": return "Глубокая работа"
        case "zh-Hans": return "深度工作"
        case "es-419": return "Trabajo profundo"
        case "pt-BR": return "Trabalho profundo"
        default: return "Deep work"
        }
    }

    static func addEntryNotes(for localeIdentifier: String) -> String {
        switch localeIdentifier {
        case "ru": return "Офлайн-очередь отправлена"
        case "zh-Hans": return "离线队列已上线"
        case "es-419": return "Saqué la cola sin conexión"
        case "pt-BR": return "Subi a fila offline"
        default: return "Shipped the offline queue"
        }
    }

    static let addEntryText = "Deep work"
    static let addEntryCategoryIDs = [workID]
    static let addEntryNotes = "Shipped the offline queue"
    static func addEntryCategoryIDs(for _: String) -> [String] { [workID] }
    /// Reference-day wall time for the sample interval (hour/minute) and
    /// its duration in minutes. Minute-exact so the sheet pills render it
    /// without flooring drift.
    static let addEntryStartHour = 8
    static let addEntryStartMinute = 0
    static let addEntryDurationMinutes = 60

    /// Sample Start/End on the reference day in the request calendar.
    static func addEntryInterval(calendar: Calendar, referenceDate: Date) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: referenceDate)
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = addEntryStartHour
        comps.minute = addEntryStartMinute
        comps.second = 0
        let start = calendar.date(from: comps)!
        return (start, start.addingTimeInterval(TimeInterval(addEntryDurationMinutes * 60)))
    }

    // MARK: - Entries (daysAgo from the reference Tuesday, local wall time)

    struct EntrySpec {
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let durationMinutes: Int
        let text: String
        let categoryIDs: [String]
        let notes: String
    }

    static let entries: [EntrySpec] = [
        EntrySpec(daysAgo: 0, hour: 6, minute: 40, durationMinutes: 30, text: "Morning run", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 0, hour: 7, minute: 30, durationMinutes: 45, text: "Breakfast tacos", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 1, hour: 8, minute: 0, durationMinutes: 25, text: "Morning run", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 1, hour: 12, minute: 15, durationMinutes: 45, text: "Lunch break", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 1, hour: 19, minute: 0, durationMinutes: 60, text: "Gym", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 2, hour: 9, minute: 0, durationMinutes: 50, text: "Farmers market", categoryIDs: [hobbyID], notes: ""),
        EntrySpec(daysAgo: 2, hour: 14, minute: 0, durationMinutes: 90, text: "ACL festival", categoryIDs: [entertainmentID, hobbyID], notes: ""),
        EntrySpec(daysAgo: 2, hour: 21, minute: 30, durationMinutes: 40, text: "Reading", categoryIDs: [educationID], notes: ""),
        EntrySpec(daysAgo: 3, hour: 7, minute: 30, durationMinutes: 70, text: "Barton Springs swim", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 3, hour: 12, minute: 0, durationMinutes: 60, text: "Tacos", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 3, hour: 20, minute: 0, durationMinutes: 105, text: "Live music", categoryIDs: [entertainmentID], notes: ""),
        EntrySpec(daysAgo: 4, hour: 9, minute: 0, durationMinutes: 120, text: "Deep work", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 4, hour: 18, minute: 30, durationMinutes: 45, text: "Evening walk", categoryIDs: [relaxID], notes: ""),
        EntrySpec(daysAgo: 5, hour: 8, minute: 30, durationMinutes: 30, text: "Coffee", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 5, hour: 10, minute: 0, durationMinutes: 90, text: "Code review", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 5, hour: 22, minute: 0, durationMinutes: 35, text: "Reading", categoryIDs: [educationID], notes: ""),
        EntrySpec(daysAgo: 6, hour: 7, minute: 0, durationMinutes: 40, text: "Yoga", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 6, hour: 13, minute: 0, durationMinutes: 60, text: "Team lunch", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 7, hour: 8, minute: 0, durationMinutes: 55, text: "Grocery run", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 7, hour: 15, minute: 0, durationMinutes: 90, text: "Quarterly planning workshop with the platform team", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 7, hour: 19, minute: 30, durationMinutes: 70, text: "Football night", categoryIDs: [sportID, entertainmentID], notes: ""),
        EntrySpec(daysAgo: 8, hour: 9, minute: 30, durationMinutes: 120, text: "Deep work", categoryIDs: [workID], notes: "Shipped the offline queue"),
        EntrySpec(daysAgo: 8, hour: 18, minute: 0, durationMinutes: 25, text: "coffee", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 9, hour: 10, minute: 0, durationMinutes: 45, text: "Brunch", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 9, hour: 16, minute: 0, durationMinutes: 60, text: "Side project", categoryIDs: [hobbyID], notes: ""),
        EntrySpec(daysAgo: 9, hour: 21, minute: 0, durationMinutes: 30, text: "Inbox zero", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 10, hour: 8, minute: 0, durationMinutes: 65, text: "Trail run", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 10, hour: 13, minute: 30, durationMinutes: 50, text: "Lunch break", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 10, hour: 19, minute: 0, durationMinutes: 110, text: "Live music", categoryIDs: [entertainmentID], notes: ""),
        EntrySpec(daysAgo: 11, hour: 10, minute: 30, durationMinutes: 45, text: "Design sync", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 11, hour: 20, minute: 30, durationMinutes: 90, text: "Movie night", categoryIDs: [entertainmentID], notes: ""),
        EntrySpec(daysAgo: 12, hour: 7, minute: 15, durationMinutes: 30, text: "Morning run", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 12, hour: 12, minute: 0, durationMinutes: 40, text: "Tacos", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 12, hour: 18, minute: 30, durationMinutes: 55, text: "Gym", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 13, hour: 9, minute: 0, durationMinutes: 100, text: "Deep work", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 13, hour: 21, minute: 30, durationMinutes: 25, text: "Reading", categoryIDs: [educationID], notes: ""),
        EntrySpec(daysAgo: 14, hour: 8, minute: 0, durationMinutes: 35, text: "Coffee", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 14, hour: 14, minute: 0, durationMinutes: 75, text: "Code review", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 14, hour: 19, minute: 0, durationMinutes: 60, text: "Evening walk", categoryIDs: [relaxID], notes: ""),
        EntrySpec(daysAgo: 15, hour: 7, minute: 45, durationMinutes: 50, text: "Yoga", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 15, hour: 12, minute: 30, durationMinutes: 45, text: "Lunch break", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 16, hour: 9, minute: 30, durationMinutes: 55, text: "Farmers market", categoryIDs: [hobbyID], notes: ""),
        EntrySpec(daysAgo: 16, hour: 15, minute: 0, durationMinutes: 80, text: "Side project", categoryIDs: [hobbyID], notes: ""),
        EntrySpec(daysAgo: 16, hour: 20, minute: 0, durationMinutes: 45, text: "Reading", categoryIDs: [educationID], notes: ""),
        EntrySpec(daysAgo: 17, hour: 8, minute: 30, durationMinutes: 75, text: "Barton Springs swim", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 17, hour: 12, minute: 30, durationMinutes: 60, text: "BBQ", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 17, hour: 21, minute: 0, durationMinutes: 95, text: "Football night", categoryIDs: [sportID, entertainmentID], notes: ""),
        EntrySpec(daysAgo: 18, hour: 10, minute: 0, durationMinutes: 110, text: "Deep work", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 18, hour: 19, minute: 30, durationMinutes: 50, text: "Evening walk", categoryIDs: [relaxID], notes: ""),
        EntrySpec(daysAgo: 19, hour: 7, minute: 0, durationMinutes: 40, text: "Morning run", categoryIDs: [sportID], notes: ""),
        EntrySpec(daysAgo: 19, hour: 11, minute: 0, durationMinutes: 65, text: "Grocery run", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 19, hour: 18, minute: 0, durationMinutes: 85, text: "Live music", categoryIDs: [entertainmentID], notes: ""),
        EntrySpec(daysAgo: 20, hour: 8, minute: 30, durationMinutes: 30, text: "coffee", categoryIDs: [foodID], notes: ""),
        EntrySpec(daysAgo: 20, hour: 13, minute: 0, durationMinutes: 70, text: "Code review", categoryIDs: [workID], notes: ""),
        EntrySpec(daysAgo: 20, hour: 20, minute: 0, durationMinutes: 40, text: "Evening walk", categoryIDs: [relaxID], notes: ""),
    ]

    // MARK: - Localized deck texts (text-only adaptation)

    /// Entry texts in fixture order (index 1 = `texts[0]`), from
    /// `openspec/changes/app-store-screenshot-pilot/decks/<locale>.json`.
    /// Durations, ordering, and ordered category links come from `entries`
    /// above — these arrays supply text/notes only.
    private static let ruEntryTexts = [
        "Утренняя пробежка",
        "Сырники на завтрак",
        "Утренняя пробежка",
        "Перерыв на обед",
        "Спортзал",
        "Фермерский рынок",
        "Пикник Афиши",
        "Чтение",
        "Заплыв в Серебряном бору",
        "Пельмени",
        "Живой концерт",
        "Глубокая работа",
        "Вечерняя прогулка",
        "Кофе",
        "Проверка кода",
        "Чтение",
        "Йога",
        "Обед с командой",
        "Закупка продуктов",
        "Квартальное планирование с платформенной командой",
        "Футбольный вечер",
        "Глубокая работа",
        "кофе",
        "Поздний завтрак",
        "Свой проект",
        "Разбор почты",
        "Пробежка в Битце",
        "Перерыв на обед",
        "Живой концерт",
        "Созвон по дизайну",
        "Киновечер",
        "Утренняя пробежка",
        "Пельмени",
        "Спортзал",
        "Глубокая работа",
        "Чтение",
        "Кофе",
        "Проверка кода",
        "Вечерняя прогулка",
        "Йога",
        "Перерыв на обед",
        "Фермерский рынок",
        "Свой проект",
        "Чтение",
        "Заплыв в Серебряном бору",
        "Шашлыки",
        "Футбольный вечер",
        "Глубокая работа",
        "Вечерняя прогулка",
        "Утренняя пробежка",
        "Закупка продуктов",
        "Живой концерт",
        "кофе",
        "Проверка кода",
        "Вечерняя прогулка",
    ]

    private static let zhEntryTexts = [
        "晨跑",
        "生煎包",
        "晨跑",
        "午餐休息",
        "健身",
        "逛菜市场",
        "草莓音乐节",
        "读书",
        "游泳馆游泳",
        "牛肉面",
        "现场演出",
        "深度工作",
        "滨江散步",
        "喝咖啡",
        "代码评审",
        "读书",
        "瑜伽",
        "团队午餐",
        "超市采购",
        "和平台团队的季度规划研讨会",
        "足球之夜",
        "深度工作",
        "咖啡",
        "早午餐",
        "个人小项目",
        "清空收件箱",
        "世纪公园跑步",
        "午餐休息",
        "现场演出",
        "设计同步会",
        "电影之夜",
        "晨跑",
        "牛肉面",
        "健身",
        "深度工作",
        "读书",
        "喝咖啡",
        "代码评审",
        "滨江散步",
        "瑜伽",
        "午餐休息",
        "逛菜市场",
        "个人小项目",
        "读书",
        "游泳馆游泳",
        "户外烧烤",
        "足球之夜",
        "深度工作",
        "滨江散步",
        "晨跑",
        "超市采购",
        "现场演出",
        "咖啡",
        "代码评审",
        "滨江散步",
    ]

    private static let esEntryTexts = [
        "Carrera matutina",
        "Tacos de guisado",
        "Carrera matutina",
        "Hora de comer",
        "Gimnasio",
        "Tianguis",
        "Vive Latino",
        "Lectura",
        "Alberca Olímpica",
        "Tacos",
        "Música en vivo",
        "Trabajo profundo",
        "Paseo nocturno",
        "Café",
        "Revisión de código",
        "Lectura",
        "Yoga",
        "Comida de equipo",
        "Ir al súper",
        "Taller de planeación trimestral con el equipo de plataforma",
        "Noche de futbol",
        "Trabajo profundo",
        "café",
        "Almuerzo",
        "Proyecto personal",
        "Bandeja vacía",
        "Chapultepec",
        "Hora de comer",
        "Música en vivo",
        "Junta de diseño",
        "Noche de cine",
        "Carrera matutina",
        "Tacos",
        "Gimnasio",
        "Trabajo profundo",
        "Lectura",
        "Café",
        "Revisión de código",
        "Paseo nocturno",
        "Yoga",
        "Hora de comer",
        "Tianguis",
        "Proyecto personal",
        "Lectura",
        "Alberca Olímpica",
        "Parrillada",
        "Noche de futbol",
        "Trabajo profundo",
        "Paseo nocturno",
        "Carrera matutina",
        "Ir al súper",
        "Música en vivo",
        "café",
        "Revisión de código",
        "Paseo nocturno",
    ]

    private static let ptEntryTexts = [
        "Corrida matinal",
        "Tapioca na padaria",
        "Corrida matinal",
        "Pausa para o almoço",
        "Academia",
        "Feira livre",
        "Virada Cultural",
        "Leitura",
        "Natação no Sesc",
        "Pastel",
        "Música ao vivo",
        "Trabalho profundo",
        "Caminhada noturna",
        "Café",
        "Revisão de código",
        "Leitura",
        "Ioga",
        "Almoço em equipe",
        "Compras no mercado",
        "Workshop de planejamento trimestral com o time da plataforma",
        "Noite de futebol",
        "Trabalho profundo",
        "café",
        "Brunch de domingo",
        "Projeto pessoal",
        "Caixa de entrada zerada",
        "Corrida na trilha",
        "Pausa para o almoço",
        "Música ao vivo",
        "Alinhamento de design",
        "Noite de cinema",
        "Corrida matinal",
        "Pastel",
        "Academia",
        "Trabalho profundo",
        "Leitura",
        "Café",
        "Revisão de código",
        "Caminhada noturna",
        "Ioga",
        "Pausa para o almoço",
        "Feira livre",
        "Projeto pessoal",
        "Leitura",
        "Natação no Sesc",
        "Churrasco",
        "Noite de futebol",
        "Trabalho profundo",
        "Caminhada noturna",
        "Corrida matinal",
        "Compras no mercado",
        "Música ao vivo",
        "café",
        "Revisão de código",
        "Caminhada noturna",
    ]

    /// Localized entry texts in fixture order, or nil for the English
    /// deck (which uses `entries` directly) and unknown locales.
    static func localizedEntryTexts(for localeIdentifier: String) -> [String]? {
        switch localeIdentifier {
        case "ru": return ruEntryTexts
        case "zh-Hans": return zhEntryTexts
        case "es-419": return esEntryTexts
        case "pt-BR": return ptEntryTexts
        default: return nil
        }
    }

    /// Localized specs: shared durations/ordering/links from `entries`
    /// with deck text/notes applied. English (and unknown) locales return
    /// the base English specs unchanged.
    static func entries(for localeIdentifier: String) -> [EntrySpec] {
        guard let texts = localizedEntryTexts(for: localeIdentifier) else {
            return entries
        }
        let notesValue = addEntryNotes(for: localeIdentifier)
        precondition(texts.count == entries.count, "Localized deck length mismatch for \(localeIdentifier)")
        return entries.enumerated().map { index, spec in
            EntrySpec(
                daysAgo: spec.daysAgo,
                hour: spec.hour,
                minute: spec.minute,
                durationMinutes: spec.durationMinutes,
                text: texts[index],
                categoryIDs: spec.categoryIDs,
                notes: index == 21 ? notesValue : ""
            )
        }
    }

    /// Materializes stable-ID committed entries anchored to the reference
    /// Tuesday in the request calendar. `stamp` dates record metadata.
    static func buildEntries(calendar: Calendar, stamp: Date) -> [TimeEntry] {
        buildEntries(calendar: calendar, stamp: stamp, localeIdentifier: "en")
    }

    /// Localized materialization: same stable IDs, durations, ordering,
    /// and ordered category links — only text/notes vary by deck.
    static func buildEntries(calendar: Calendar, stamp: Date, localeIdentifier: String) -> [TimeEntry] {
        let referenceDay = calendar.startOfDay(for: ScreenshotRequestLoader.referenceDate(
            iso: ScreenshotCaptureRequest.pinnedReferenceISO,
            timeZone: calendar.timeZone
        )!)
        return entries(for: localeIdentifier).enumerated().map { index, spec in
            let day = calendar.date(byAdding: .day, value: -spec.daysAgo, to: referenceDay)!
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = spec.hour
            comps.minute = spec.minute
            comps.second = 0
            let start = calendar.date(from: comps)!
            let end = start.addingTimeInterval(TimeInterval(spec.durationMinutes * 60))
            return TimeEntry(
                id: String(format: "shot-e%02d", index + 1),
                activityText: spec.text,
                startedAt: start,
                endedAt: end,
                durationSeconds: spec.durationMinutes * 60,
                categoryIDs: spec.categoryIDs,
                notes: spec.notes,
                createdAt: end,
                updatedAt: end
            )
        }
    }
}
#endif
