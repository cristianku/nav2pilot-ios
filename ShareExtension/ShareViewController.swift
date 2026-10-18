import Nav2PilotKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Nav2Pilot" in the share sheet of Google Maps, Apple Maps or any app that shares a link or text.
///
/// The extension resolves and sends the destination itself, so the user stays in the map app.
/// It reads the devices and the token that the app stored (App Group and shared Keychain group).
final class ShareViewController: UIViewController {
    private let viewModel = AppContainer.makeViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(viewModel: viewModel, onDone: { [weak self] in
            self?.finish()
        })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task {
            await loadSharedContent()
        }
    }

    private func loadSharedContent() async {
        var inputItems: [NSExtensionItem] = []
        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            inputItems = items
        }
        let shared = await SharedItems.read(inputItems)

        let resolveTask = Task {
            await viewModel.handleShare(text: shared.text, subject: shared.subject)
        }
        await viewModel.start()
        // Without a shared App Group (for example with a signing team that has none) the extension sees
        // no stored devices; it can still list them from the comma account.
        if viewModel.devices.isEmpty && viewModel.hasToken {
            await viewModel.refreshDevices()
        }
        await resolveTask.value
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

/// Text, links and title of the shared items, flattened to what ShareTextParser expects:
/// text lines first, then the link.
enum SharedItems {
    struct Content {
        let text: String
        let subject: String
    }

    static func read(_ items: [NSExtensionItem]) async -> Content {
        var lines: [String] = []
        var links: [String] = []
        var subject = ""

        for item in items {
            if subject.isEmpty, let title = item.attributedTitle?.string {
                subject = title
            }
            if let content = item.attributedContentText?.string {
                if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append(content)
                }
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let link = await loadLink(provider) {
                        links.append(link)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(provider) {
                        lines.append(text)
                    }
                }
            }
        }

        var text = lines.joined(separator: "\n")
        for link in links {
            if !text.contains(link) {
                text += "\n" + link
            }
        }
        return Content(text: text, subject: subject)
    }

    private static func loadLink(_ provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) else {
            return nil
        }
        if let url = item as? URL {
            if url.isFileURL {
                return nil
            }
            return url.absoluteString
        }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url.absoluteString
        }
        if let text = item as? String {
            return text
        }
        return nil
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) else {
            return nil
        }
        if let text = item as? String {
            return text
        }
        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

struct ShareView: View {
    let viewModel: MainViewModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.resolving {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Finding the location…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .cardStyle()
                    }
                    if !viewModel.resolveError.isEmpty {
                        Label(viewModel.resolveError, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Theme.error)
                            .padding(16)
                            .cardStyle()
                    }
                    if !viewModel.choices.isEmpty {
                        ChoicesCard(viewModel: viewModel)
                    }
                    if !viewModel.resolving && viewModel.resolveError.isEmpty {
                        DestinationCard(viewModel: viewModel, showsMapLinks: false, allowsClear: false)
                    }
                    DeviceCard(viewModel: viewModel, onOpenDevices: nil, showsClearOnDevice: false)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SendBar(viewModel: viewModel)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandHeader(logoSize: 26, titleFont: .headline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
