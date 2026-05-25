//
//  ViewImageRenderer.swift
//  Split Rewards
//

import SwiftUI
import UIKit

extension View {
    func renderAsImage(size: CGSize) -> UIImage {
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: self.frame(width: size.width, height: size.height))
            renderer.scale = UIScreen.main.scale
            return renderer.uiImage ?? UIImage()
        } else {
            let controller = UIHostingController(rootView: self)
            controller.view.bounds = CGRect(origin: .zero, size: size)
            controller.view.backgroundColor = .clear
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
    }
}
