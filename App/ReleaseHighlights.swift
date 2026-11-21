import SwiftUI
import Nav2PilotKit

struct ReleaseHighlights: View {
    static let edition = "parking-cards-" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1")
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
        Slide(label: "Parking on the map", title: "Find a free parking space",
              body: "Tap Parking below search. Green means spaces available, orange means only a few, and red means full. A gray P has no recent count.",
              symbol: "parkingsign", example: "12 spaces free", accent: .mint),
        Slide(label: "Favorites", title: "Your car park at a glance",
              body: "Tap a pin, then the heart to save the place without changing your route. Your favorite car parks show recent free-space counts right in the list.",
              symbol: "heart.fill", example: "12 spaces free", accent: .mint),
        Slide(label: "On the map", title: "Take a look before you go",
              body: "Pull up the handle for opening hours, a photo and visitor reviews when available. Pull down to return to the map. Your route stays the same.",
              symbol: "mappin", example: "Rebgasse", accent: Color(red: 0.40, green: 0.91, blue: 0.89)),
        Slide(label: "Restaurants", title: "Book from the place card",
              body: "When a restaurant lists a booking link, tap Book a table to open it. If only a website or phone number is listed, you can visit the site or call instead.",
              symbol: "fork.knife", example: "Book a table", accent: .orange),
        Slide(label: "In search", title: "Your usual places, one tap away",
              body: "Save Home or Work in a destination’s details. Open search for them and your recently sent places. You can also prepare a search with Siri or Shortcuts.",
              symbol: "heart.fill", example: "Home  ·  Work", accent: Color(red: 0.65, green: 0.81, blue: 1)),
        Slide(label: "Feedback", title: "Tell us what you think",
              body: "Send feedback from Settings whenever you like. If we ask in the app, you can write now, come back later, or turn off reminders.",
              symbol: "bubble.left.fill", example: "Send feedback", accent: Color(red: 0.52, green: 0.87, blue: 0.90))
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
                                    Group {
                                        if index == 0 { parkingArt }
                                        else { art(slide, example: false) }
                                    }
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

    private var parkingArt: some View {
        GeometryReader { geo in
            ZStack {
                Image("ParkingHarbour").resizable().scaledToFill().frame(width:geo.size.width,height:geo.size.height).clipped()
                ForEach(0..<4,id:\.self) { i in
                    let labels = ["P 12","P 3","P 0","P"]
                    let colors: [BaselParking.Level] = [.available,.few,.full,.unknown]
                    Text(verbatim:labels[i]).font(i == 0 ? .title3.bold():.caption.bold())
                        .foregroundStyle(.white).padding(.vertical,5).padding(.horizontal,10)
                        .background(Color(uiColor: colors[i].badgeColor),in:Capsule())
                        .overlay(Capsule().stroke(.white,lineWidth:2)).shadow(radius:2)
                        .position(x:geo.size.width * [0.30,0.70,0.55,0.20][i], y:geo.size.height * [0.44,0.50,0.79,0.82][i])
                }
            }
            .overlay(alignment:.topTrailing) {
                Label("Parking",systemImage:"parkingsign").font(.caption.bold()).foregroundStyle(.white)
                    .padding(8).background(Theme.brand,in:Capsule()).padding(10)
            }
            .overlay(alignment:.topLeading) {
                Text("Example").font(.caption2.bold()).foregroundStyle(.white).padding(6).background(.black.opacity(0.7),in:Capsule()).padding(10)
            }
        }.clipShape(RoundedRectangle(cornerRadius:24)).accessibilityHidden(true)
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
