import UIKit

/// Pixel verdicts for the capture-only hold harness (GH #238).
///
/// Swift mirror of the runner-side geometry logic in
/// `scripts/screenshots/executor.py` (`ISLAND_REGIONS`, `EXPANDED_REGIONS`,
/// `APP_CHROME_BAND_FRAC`, `SHEET_BAND_FRAC` plus thresholds) — reused
/// conceptually, with no dependency: this bundle cannot import the Python
/// runner. Boxes are pinned from live headless pixels only (see the runner
/// comments); any other geometry is unattested and yields an explicit
/// no-claim verdict, never a pass. No private API: screenshots come from
/// `XCUIScreen`, pixels via CoreGraphics. Capture-only: no app code is
/// referenced or changed.
enum HoldHarnessPixels {
    /// Top-first RGBA pixels decoded from a screenshot PNG.
    struct DecodedScreenshot {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    struct IslandVerdict {
        let live: Bool
        let darkFrac: Double
        let bright: Int
        let reason: String
    }

    struct ExpandedVerdict {
        let expanded: Bool
        let darkFrac: Double
        let bright: Int
        let reason: String
    }

    struct AppChromeVerdict {
        let app: Bool
        let share: Double
        let reason: String
    }

    /// Pill-mass floor inside the island box (runner `PILL_DARK_FRAC_MIN`).
    static let pillDarkFracMin = 0.40
    /// Live-content floor inside the island box (runner `PILL_CONTENT_MIN`).
    static let pillContentMin = 200
    /// Card-mass floor in the expanded band (runner `EXPANDED_DARK_FRAC_MIN`).
    static let expandedDarkFracMin = 0.30
    /// Card-content floor in the expanded band (runner `EXPANDED_BRIGHT_MIN`).
    static let expandedBrightMin = 500
    /// App-chrome probe band as height fractions (runner
    /// `APP_CHROME_BAND_FRAC`).
    static let appChromeBandFrac = (0.836, 0.906)
    /// Uniform-chrome share floor (runner `APP_CHROME_SHARE_MIN`).
    static let appChromeShareMin = 0.90
    /// Consent-sheet band as width/height fractions (runner
    /// `SHEET_BAND_FRAC`).
    static let sheetBandFrac = (0.136, 0.864, 0.348, 0.627)

    /// Attested island box (x0, x1, y0, y1) from the display top-left, or
    /// nil for unattested geometry (no claim, never a pass).
    static func islandBox(width: Int, height: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int)? {
        switch (width, height) {
        case (1320, 2868):
            return (400, 990, 35, 160)
        case (1206, 2622):
            return (400, 805, 30, 165)
        default:
            return nil
        }
    }

    /// Attested expanded-card band below the island, or nil when unattested.
    static func expandedBox(width: Int, height: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int)? {
        switch (width, height) {
        case (1320, 2868):
            return (350, 970, 180, 650)
        case (1206, 2622):
            return (320, 886, 180, 594)
        default:
            return nil
        }
    }

    /// Decodes screenshot PNG data to top-first RGBA. Nil when undecodable.
    static func decode(_ data: Data) -> DecodedScreenshot? {
        guard let source = UIImage(data: data), let cg = source.cgImage else {
            return nil
        }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else {
            return nil
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else {
                return false
            }
            guard let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            // CGImage draws bottom-up; flip so row 0 is the display top,
            // matching the runner's top-first PNG decode.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        return DecodedScreenshot(width: width, height: height, rgba: rgba)
    }

    /// Live-pill verdict: mass AND bright content both required.
    static func islandVerdict(_ image: DecodedScreenshot) -> IslandVerdict {
        guard let box = islandBox(width: image.width, height: image.height) else {
            return IslandVerdict(
                live: false,
                darkFrac: 0,
                bright: 0,
                reason: "island region unattested for \(image.width)x\(image.height); no island claim"
            )
        }
        let counts = countDarkBright(
            image: image,
            x0: box.x0,
            x1: box.x1,
            y0: box.y0,
            y1: box.y1
        )
        let frac = Double(counts.dark) / Double(max(1, counts.total))
        guard frac >= pillDarkFracMin else {
            return IslandVerdict(
                live: false,
                darkFrac: frac,
                bright: counts.bright,
                reason: "no pill mass in island region; no island claim"
            )
        }
        guard counts.bright >= pillContentMin else {
            return IslandVerdict(
                live: false,
                darkFrac: frac,
                bright: counts.bright,
                reason: "idle pill without live content; no island claim"
            )
        }
        return IslandVerdict(
            live: true,
            darkFrac: frac,
            bright: counts.bright,
            reason: "live pill content verified"
        )
    }

    /// Image-derived press point: centroid of bright live content inside the
    /// verified island box, normalized to 0...1. Nil unless the box is
    /// attested and content exists — the caller must refuse the hold then,
    /// never press blind.
    static func islandPressPoint(_ image: DecodedScreenshot) -> (x: Double, y: Double)? {
        guard let box = islandBox(width: image.width, height: image.height) else {
            return nil
        }
        var sumX = 0
        var sumY = 0
        var mass = 0
        for y in box.y0...box.y1 {
            let base = y * image.width * 4
            for x in box.x0...box.x1 {
                let off = base + x * 4
                guard off + 2 < image.rgba.count else {
                    continue
                }
                guard isBright(image.rgba[off], image.rgba[off + 1], image.rgba[off + 2]) else {
                    continue
                }
                sumX += x
                sumY += y
                mass += 1
            }
        }
        guard mass > 0 else {
            return nil
        }
        return (
            x: Double(sumX) / Double(mass) / Double(image.width),
            y: Double(sumY) / Double(mass) / Double(image.height)
        )
    }

    /// Expanded-card verdict: card-band mass AND bright content required.
    static func expandedVerdict(_ image: DecodedScreenshot) -> ExpandedVerdict {
        guard let box = expandedBox(width: image.width, height: image.height) else {
            return ExpandedVerdict(
                expanded: false,
                darkFrac: 0,
                bright: 0,
                reason: "expanded band unattested for \(image.width)x\(image.height); no expanded claim"
            )
        }
        let counts = countDarkBright(
            image: image,
            x0: box.x0,
            x1: box.x1,
            y0: box.y0,
            y1: box.y1
        )
        let frac = Double(counts.dark) / Double(max(1, counts.total))
        guard frac >= expandedDarkFracMin else {
            return ExpandedVerdict(
                expanded: false,
                darkFrac: frac,
                bright: counts.bright,
                reason: "no card mass below the island; no expanded claim"
            )
        }
        guard counts.bright >= expandedBrightMin else {
            return ExpandedVerdict(
                expanded: false,
                darkFrac: frac,
                bright: counts.bright,
                reason: "dark band without card content; no expanded claim"
            )
        }
        return ExpandedVerdict(
            expanded: true,
            darkFrac: frac,
            bright: counts.bright,
            reason: "expanded card mass verified"
        )
    }

    /// App-foreground guard: uniform near-white chrome in the probe band
    /// means a tap opened the app instead of expanding — staged cards are
    /// refused on these pixels, never by eye.
    static func appChromeVerdict(_ image: DecodedScreenshot) -> AppChromeVerdict {
        let y0 = Int(Double(image.height) * appChromeBandFrac.0)
        let y1 = Int(Double(image.height) * appChromeBandFrac.1)
        var buckets: [Int: Int] = [:]
        var total = 0
        var y = y0
        while y <= y1 {
            let base = y * image.width * 4
            var x = 0
            while x < image.width {
                let off = base + x * 4
                guard off + 2 < image.rgba.count else {
                    break
                }
                let key = Int(image.rgba[off]) / 32 * 64
                    + Int(image.rgba[off + 1]) / 32 * 8
                    + Int(image.rgba[off + 2]) / 32
                buckets[key, default: 0] += 1
                total += 1
                x += 2
            }
            y += 2
        }
        guard total > 0, let top = buckets.max(by: { $0.value < $1.value }) else {
            return AppChromeVerdict(app: false, share: 0, reason: "empty probe band; no app claim")
        }
        let share = Double(top.value) / Double(total)
        let light = top.key / 64 >= 6 && top.key / 8 % 8 >= 6 && top.key % 8 >= 6
        guard light, share >= appChromeShareMin else {
            return AppChromeVerdict(app: false, share: share, reason: "wallpaper variance; SpringBoard held")
        }
        return AppChromeVerdict(app: true, share: share, reason: "uniform near-white app chrome; app foregrounded")
    }

    /// Supporting evidence for the consent test: light-pixel fraction in the
    /// sheet band (a visible system alert body reads high, plain wallpaper
    /// low). Advisory only — dismissal is gated on the alert AX surface plus
    /// the re-screenshot pair, never on this number alone.
    static func sheetLightFrac(_ image: DecodedScreenshot) -> Double? {
        let frac = sheetBandFrac
        let x0 = Int(Double(image.width) * frac.0)
        let x1 = Int(Double(image.width) * frac.1)
        let y0 = Int(Double(image.height) * frac.2)
        let y1 = Int(Double(image.height) * frac.3)
        var light = 0
        var total = 0
        var y = y0
        while y <= y1 {
            let base = y * image.width * 4
            var x = x0
            while x <= x1 {
                let off = base + x * 4
                guard off + 2 < image.rgba.count else {
                    break
                }
                if isBright(image.rgba[off], image.rgba[off + 1], image.rgba[off + 2]) {
                    light += 1
                }
                total += 1
                x += 4
            }
            y += 4
        }
        guard total > 0 else {
            return nil
        }
        return Double(light) / Double(total)
    }

    private static func isDark(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        r < 24 && g < 24 && b < 24
    }

    private static func isBright(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        r > 150 || g > 150 || b > 150
    }

    private static func countDarkBright(
        image: DecodedScreenshot,
        x0: Int,
        x1: Int,
        y0: Int,
        y1: Int
    ) -> (dark: Int, bright: Int, total: Int) {
        var dark = 0
        var bright = 0
        var total = 0
        for y in y0...y1 {
            let base = y * image.width * 4
            for x in x0...x1 {
                let off = base + x * 4
                guard off + 2 < image.rgba.count else {
                    continue
                }
                total += 1
                if isDark(image.rgba[off], image.rgba[off + 1], image.rgba[off + 2]) {
                    dark += 1
                }
                if isBright(image.rgba[off], image.rgba[off + 1], image.rgba[off + 2]) {
                    bright += 1
                }
            }
        }
        return (dark, bright, total)
    }
}
