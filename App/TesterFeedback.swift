import Nav2PilotKit
import SwiftUI

@MainActor @Observable final class TesterFeedback {
    private let defaults: UserDefaults
    var message = ""
    private(set) var busy = false
    private(set) var failed = false
    private(set) var delivered = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func visit(now: Date = Date()) -> Bool {
        guard !defaults.bool(forKey: "feedback.stopped") else { return false }
        let date = Calendar.current.startOfDay(for: now)
        if let last = defaults.object(forKey: "feedback.day") as? Date, date <= last { return false }
        defaults.set(date, forKey: "feedback.day")
        let days = min(3, defaults.integer(forKey: "feedback.days") + 1)
        defaults.set(days, forKey: "feedback.days")
        guard days >= 3, date >= (defaults.object(forKey: "feedback.next") as? Date ?? .distantPast) else { return false }
        defaults.set(Calendar.current.date(byAdding: .day, value: 60, to: date), forKey: "feedback.next")
        return true
    }
    func stopAsking() { defaults.set(true, forKey: "feedback.stopped") }
    func prepare() { if !busy { failed = false; delivered = false } }
    var metadata: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Nav2Pilot feedback\nformat: 1\napp: \(version) (\(build))\nplatform: iOS"
    }
    var report: String { metadata + "\n\n[message]\n" + message.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" }
    func send() async {
        guard !busy, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "FeedbackClientKey") as? String,
              !key.isEmpty, !key.contains("$(") else { failed = true; return }
        busy = true
        defer { busy = false }
        let request = HttpRequest(method: "POST", url: "https://feedback.14bodhi.com/v1/feedback",
            headers: ["Content-Type": "text/plain; charset=utf-8", "X-App": "nav2pilot", "X-App-Key": key],
            body: report, followRedirects: false, timeoutSeconds: 10)
        let result = try? await URLSessionHttpClient(userAgent: "Nav2Pilot (iOS)").execute(request)
        if result?.code == 201 { stopAsking(); delivered = true; failed = false; message = "" }
        else { failed = true }
    }
    var mailURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"; c.path = "admin@14bodhi.com"
        c.queryItems = [URLQueryItem(name: "subject", value: "Nav2Pilot feedback"), URLQueryItem(name: "body", value: report)]
        return c.url
    }
}

struct TesterFeedbackForm: View {
    @Bindable var model: TesterFeedback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if model.delivered {
                    Label("Feedback received. Thank you!", systemImage: "checkmark.circle.fill")
                } else {
                    Section {
                        Text("Your message and the details below will go to the Nav2Pilot feedback server.")
                        Text(model.metadata).font(.caption.monospaced()).foregroundStyle(.secondary)
                        TextField("Your feedback", text: $model.message, axis: .vertical)
                            .lineLimit(3...7)
                            .onChange(of: model.message) { _, text in
                                if text.utf8.count > 12000 {
                                    var result = ""
                                    var bytes = 0
                                    for character in text {
                                        bytes += String(character).utf8.count
                                        if bytes > 12000 { break }
                                        result.append(character)
                                    }
                                    model.message = result
                                }
                            }
                            .disabled(model.busy)
                    }
                    if model.failed {
                        Section {
                            Text("Delivery wasn’t confirmed. Your message is still here.")
                            if let url = model.mailURL { Link("Use email", destination: url) }
                            ShareLink(item: model.report)
                        }
                    }
                    Button { Task { await model.send() } } label: {
                        if model.busy { ProgressView() } else { Text("Send") }
                    }.disabled(model.busy || model.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Send feedback")
            .toolbar { Button("Done") { dismiss() }.disabled(model.busy) }
        }
        .interactiveDismissDisabled(model.busy)
    }
}
