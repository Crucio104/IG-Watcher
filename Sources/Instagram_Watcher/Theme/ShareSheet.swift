import SwiftUI
import UIKit

/// Presenta lo Share Sheet nativo di iOS per salvare o condividere file di backup
public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public init(activityItems: [Any]) {
        self.items = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

public struct ShareItem: Identifiable {
    public var id: String { url.absoluteString }
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

