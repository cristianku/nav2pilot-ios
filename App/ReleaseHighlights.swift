import SwiftUI

/// Change the edition id with the slides, not on every build of the same release.
struct ReleaseHighlights: View {
    static let edition = "places-and-parking-1"
    let close: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Slide {
        let label: LocalizedStringKey
        let title: LocalizedStringKey
        let body: LocalizedStringKey
        let symbol: String
        let example: LocalizedStringKey
        let accent: Color
    }

    private static let slides = [
        Slide(label: "On the map", title: "Take a look before you go",
              body: "Tap a pin to see what’s there. Compare another place or close the card: your route stays as it is until you choose a destination or add a stop.",
              symbol: "mappin", example: "Rebgasse", accent: Color(red: 0.40, green: 0.91, blue: 0.89)),
        Slide(label: "Parking in Basel", title: "Is there room to park?",
              body: "Tap a participating garage in Basel to see how many spaces are free and when the count was updated. If there’s no recent reading, the app tells you.",
              symbol: "parkingsign", example: "12 spaces free", accent: Color(red: 0.53, green: 0.93, blue: 0.82)),
        Slide(label: "In search", title: "Your usual places, one tap away",
              body: "Save Home or Work in a destination’s details. Open search for them and your recently sent places. You can also prepare a search with Siri or Shortcuts.",
              symbol: "heart.fill", example: "Home  ·  Work", accent: Color(red: 0.65, green: 0.81, blue: 1))
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                HStack {
                    Text("What’s new").font(.headline)
                    Spacer()
                    Button("Skip", action: close).accessibilityIdentifier("highlightsSkip")
                        .frame(minHeight: 44)
                }
                HStack(spacing: 5) {
                    ForEach(Self.slides.indices, id: \.self) { index in
                        Capsule().fill(index <= page ? Theme.brand : Theme.cardBorder).frame(height: 4)
                    }
                }.accessibilityHidden(true)
                TabView(selection: $page) {
                    ForEach(Self.slides.indices, id: \.self) { index in
                        let slide = Self.slides[index]
                        GeometryReader { available in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 14) {
                                    art(slide, example: index == 1)
                                        .frame(height: proxy.size.height < 460 ? 100 : 180)
                                    HStack {
                                        Text(slide.label).font(.subheadline.bold()).foregroundStyle(Theme.brand)
                                        Spacer()
                                        Text("\(index + 1) / \(Self.slides.count)").font(.caption.monospacedDigit())
                                    }
                                    Text(slide.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                                    Text(slide.body).font(.body).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: available.size.height, alignment: .leading)
                                .padding(.horizontal, 2)
                            }.scrollBounceBehavior(.basedOnSize)
                        }.tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack {
                    if page > 0 { Button("Back") { move(-1) }.frame(minHeight: 44) }
                    Spacer()
                    Button {
                        if page == Self.slides.count - 1 { close() } else { move(1) }
                    } label: {
                        Text(page == Self.slides.count - 1 ? LocalizedStringKey("Done") : "Next")
                            .frame(minWidth: 90, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("highlightsNext")
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 8).frame(maxWidth: 540)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea()).tint(Theme.brand)
    }

    private func move(_ step: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            page = min(max(page + step, 0), Self.slides.count - 1)
        }
    }

    private func art(_ slide: Slide, example: Bool) -> some View {
        let ink = Color(red: 0.025, green: 0.115, blue: 0.21)
        return ZStack {
            LinearGradient(colors: [ink, Color(red: 0.05, green: 0.29, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                let w = size.width, h = size.height
                var streets = Path()
                for i in -1...6 {
                    streets.move(to: CGPoint(x: CGFloat(i) * w / 5, y: 0))
                    streets.addLine(to: CGPoint(x: CGFloat(i - 1) * w / 5, y: h))
                }
                for i in 0...4 {
                    streets.move(to: CGPoint(x: 0, y: CGFloat(i) * h / 3))
                    streets.addLine(to: CGPoint(x: w, y: (CGFloat(i) - 0.55) * h / 3))
                }
                ctx.stroke(streets, with: .color(.white.opacity(0.10)), lineWidth: 2)
                var route = Path()
                route.move(to: CGPoint(x: 0, y: h * 0.8))
                for (x, y): (CGFloat, CGFloat) in [(0.20, 0.72), (0.32, 0.37), (0.70, 0.37), (0.82, 0.64), (1, 0.52)] {
                    route.addLine(to: CGPoint(x: w * x, y: h * y))
                }
                ctx.stroke(route, with: .color(slide.accent.opacity(0.56)), lineWidth: 4)
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.82 - 5, y: h * 0.64 - 5, width: 10, height: 10)),
                         with: .color(slide.accent))
            }
            HStack(spacing: 10) {
                Image(systemName: slide.symbol).foregroundStyle(ink).frame(width: 34, height: 34)
                    .background(slide.accent, in: Circle())
                Text(slide.example).font(.headline).foregroundStyle(.white)
            }
            .padding(12).background(ink, in: RoundedRectangle(cornerRadius: 16))
        }
        .overlay(alignment: .bottomTrailing) {
            if example { Text("Example").font(.caption2).foregroundStyle(.white).padding(10) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityHidden(true)
    }
}
