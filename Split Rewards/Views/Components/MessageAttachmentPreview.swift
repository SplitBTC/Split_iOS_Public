//
//  MessageAttachmentPreview.swift
//  Split Rewards
//
//  Created by TeeVee on 3/23/26.
//

import SwiftUI
import QuickLook

struct MessageAttachmentPreview: UIViewControllerRepresentable {
    let item: CachedMessageAttachment

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator

        let navigationController = UINavigationController(rootViewController: controller)
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.item = item
        if let controller = uiViewController.viewControllers.first as? QLPreviewController {
            controller.dataSource = context.coordinator
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var item: CachedMessageAttachment

        init(item: CachedMessageAttachment) {
            self.item = item
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: item.localURL, title: item.fileName)
        }
    }

    private final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL, title: String) {
            self.previewItemURL = url
            self.previewItemTitle = title
        }
    }
}
