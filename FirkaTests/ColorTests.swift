import SwiftUI
import Testing
@testable import Firka

/// Our own colour pairs, measured in light and dark mode: a colour tuned on one background vanishes on the other
/// (the Live Activity can't be reached by UI tests, so this is its only check).
@Suite("Colours in light and dark mode")
struct ColorTests {
    /// WCAG contrast ratio of two colours as they look in `style`.
    func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        func luminance(_ c: Color) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
            UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &bl, alpha: &al)
            let lin = { (v: CGFloat) -> Double in let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(bl)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test("Live Activity: the green labels read on the card, the bars' empty part shows", arguments: [UIUserInterfaceStyle.light, .dark])
    func liveActivity(_ style: UIUserInterfaceStyle) {
        let card = Color.liveCard(light: style == .light)
        #expect(contrast(.liveAccent, card, style) >= 4.5, "MOST / SZÜNET text")
        #expect(contrast(.liveTrack, card, style) >= 1.5, "an empty bar must not melt into the card")
    }

    @Test("grade badges: the number reads on its colour", arguments: [UIUserInterfaceStyle.light, .dark])
    func gradeBadges(_ style: UIUserInterfaceStyle) {
        for g in 1...5 { #expect(contrast(.onGrade(g), .grade(g), style) >= 4.5, "grade \(g)") }
    }

    @Test("absence states read on the list and on the counters", arguments: [UIUserInterfaceStyle.light, .dark])
    func absenceStates(_ style: UIUserInterfaceStyle) {
        for c in [Color.justified, .unjustified, .pending] {
            #expect(contrast(c, Color(.systemBackground), style) >= 4.5)
            #expect(contrast(c, Color(.secondarySystemGroupedBackground), style) >= 4.5)
        }
    }
}
