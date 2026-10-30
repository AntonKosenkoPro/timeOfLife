import Testing
import Foundation
import LifioLiveActivityCore

/// Widget-face locale regression (pt-BR Stop showed es-419 "Detener"
/// instead of "Parar"): the appex process never sees the app's in-process
/// request-locale override and may cache a prior run's language, so faces
/// MUST resolve copy from the payload `localeIdentifier` explicitly —
/// never the appex system language. Ungated: the shared framework + app
/// bundle `.lproj` resources exist in every configuration.
@Suite("LiveActivityStrings locale")
struct LiveActivityStringsLocaleTests {

    @Test("pt-BR Stop resolves Parar, never the Spanish Detener")
    func ptBRStopIsParar() {
        #expect(LiveActivityStrings.stopTitle(localeIdentifier: "pt-BR") == "Parar")
        #expect(LiveActivityStrings.stopTitle(localeIdentifier: "pt-BR") != "Detener")
        #expect(LiveActivityStrings.stopTitle(localeIdentifier: "es-419") == "Detener")
    }

    @Test("every shipped locale resolves its own Stop title")
    func allLocalesResolveStop() {
        let expected: [(locale: String, title: String)] = [
            ("en", "Stop"),
            ("ru", "Стоп"),
            ("zh-Hans", "停止"),
            ("es-419", "Detener"),
            ("pt-BR", "Parar"),
        ]
        for (locale, title) in expected {
            #expect(LiveActivityStrings.stopTitle(localeIdentifier: locale) == title, "stop for \(locale)")
        }
    }

    @Test("accessibility labels follow the payload locale")
    func accessibilityLabelsFollowLocale() {
        #expect(LiveActivityStrings.stopAccessibilityLabel(localeIdentifier: "pt-BR") == "Parar e salvar o cronômetro")
        #expect(LiveActivityStrings.stopAccessibilityLabel(localeIdentifier: "es-419") == "Detener temporizador y guardar")
        #expect(LiveActivityStrings.runningAccessibilityLabel(text: "X", localeIdentifier: "pt-BR") == "X, cronômetro rodando")
        #expect(LiveActivityStrings.runningAccessibilityLabel(text: "X", localeIdentifier: "es-419") == "X, temporizador en curso")
        #expect(LiveActivityStrings.savedCardTitle(duration: "12:34", localeIdentifier: "pt-BR") == "Salvo 12:34")
        #expect(LiveActivityStrings.savedCardTitle(duration: "12:34", localeIdentifier: "es-419") == "Guardado 12:34")
    }

    @Test("unknown locale falls back to system resolution, never the raw key")
    func unknownLocaleFallsBack() {
        let stop = LiveActivityStrings.stopTitle(localeIdentifier: "xx-YY")
        #expect(!stop.isEmpty)
        #expect(stop != "timer.stop")
        #expect(LiveActivityLocale.localizedString("timer.stop", localeIdentifier: "xx-YY") == nil)
        #expect(LiveActivityLocale.localizedString("timer.stop", localeIdentifier: "pt-BR") == "Parar")
    }
}
