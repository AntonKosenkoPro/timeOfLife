#if DEBUG
import SwiftUI

enum NumericTimerMockupStyle: Equatable {
    case centered
    case editorial
    case split

    init?(screenName: String?) {
        guard let screenName, screenName.hasPrefix("design-numeric-") else { return nil }

        switch String(screenName.dropFirst("design-numeric-".count)) {
        case "centered": self = .centered
        case "editorial": self = .editorial
        case "split": self = .split
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .centered: "Centered"
        case .editorial: "Editorial"
        case .split: "Split units"
        }
    }
}

struct NumericTimerMockupBoard: View {
    let style: NumericTimerMockupStyle

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    Text("READY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(PrototypePalette.secondaryText)
                        .padding(.top, 8)

                    Button {} label: {
                        HStack(spacing: 7) {
                            Image(systemName: "circle.hexagongrid.fill")
                            Text("Deep work")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.headline)
                        .foregroundStyle(PrototypePalette.primaryText)
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("NumericMockupActivityButton")

                    layout

                    startButton
                        .padding(.top, 30)

                    Text("A numeric-only timer keeps the elapsed value exact and quiet.")
                        .font(.footnote)
                        .foregroundStyle(PrototypePalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .background(PrototypePalette.canvas.ignoresSafeArea())
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {} label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 19))
                    }
                    .accessibilityLabel("Profile")
                    .accessibilityIdentifier("NumericMockupProfileButton")
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Numeric timer study, \(style.name)")
    }

    private var layout: some View {
        Group {
            switch style {
            case .centered:
                centeredLayout
            case .editorial:
                editorialLayout
            case .split:
                splitLayout
            }
        }
    }

    private var centeredLayout: some View {
        VStack(spacing: 8) {
            Text("00:00")
                .font(.system(size: 92, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PrototypePalette.primaryText)
            Text("READY TO START")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(PrototypePalette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 84)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timer ready for Deep work")
        .accessibilityValue("00:00")
        .accessibilityIdentifier("NumericMockupReadout")
    }

    private var editorialLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ELAPSED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(PrototypePalette.secondaryText)
                Spacer()
                Text("READY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(PrototypePalette.accent)
            }

            Text("00:00")
                .font(.system(size: 104, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PrototypePalette.primaryText)
                .padding(.top, 8)

            Rectangle()
                .fill(PrototypePalette.hairline)
                .frame(height: 1)
                .padding(.top, 12)

            Text("Start when you are ready")
                .font(.subheadline)
                .foregroundStyle(PrototypePalette.secondaryText)
                .padding(.top, 12)
        }
        .padding(.top, 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timer ready for Deep work")
        .accessibilityValue("00:00")
        .accessibilityIdentifier("NumericMockupReadout")
    }

    private var splitLayout: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            unit(value: "00", label: "MINUTES")
            Text(":")
                .font(.system(size: 52, weight: .ultraLight, design: .rounded))
                .foregroundStyle(PrototypePalette.secondaryText)
                .padding(.bottom, 20)
            unit(value: "00", label: "SECONDS")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 102)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timer ready for Deep work")
        .accessibilityValue("00 minutes, 00 seconds")
        .accessibilityIdentifier("NumericMockupReadout")
    }

    private func unit(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 74, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PrototypePalette.primaryText)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(PrototypePalette.secondaryText)
        }
    }

    private var startButton: some View {
        Button {} label: {
            HStack(spacing: 9) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Start")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(PrototypePalette.canvas)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(PrototypePalette.primaryText)
            .clipShape(Capsule())
        }
        .accessibilityIdentifier("NumericMockupStartButton")
    }
}
#endif
