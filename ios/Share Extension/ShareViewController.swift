import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroup = "group.com.vannt.nimbleclip"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        receiveSharedURL()
    }

    private func receiveSharedURL() {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            extensionContext?.cancelRequest(withError: NSError(domain: "NimbleClipShare", code: 1))
            return
        }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            ? UTType.url.identifier : UTType.plainText.identifier
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, _ in
            let text = (value as? URL)?.absoluteString ?? value as? String
            guard let self, let text, !text.isEmpty else { return }
            UserDefaults(suiteName: self.appGroup)?.set(text, forKey: "sharedText")
            DispatchQueue.main.async {
                let url = URL(string: "ShareMedia-com.vannt.nimbleclip://share")!
                self.extensionContext?.open(url) { _ in
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }
}
