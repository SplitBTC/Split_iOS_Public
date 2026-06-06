//
//  ScreenshotProtectedView.swift
//  Split Rewards
//
//  Created by TeeVee on 5/31/26.
//

import SwiftUI
import UIKit

struct ScreenshotProtectedView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> SecureHostingContainer<Content> {
        SecureHostingContainer(rootView: content)
    }

    func updateUIView(_ uiView: SecureHostingContainer<Content>, context: Context) {
        uiView.update(rootView: content)
    }
}

final class SecureHostingContainer<Content: View>: UIView {
    private let secureTextField = UITextField()
    private let hostingController: UIHostingController<Content>
    private weak var secureContentView: UIView?

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(rootView: Content) {
        hostingController.rootView = rootView
    }

    private func configure() {
        backgroundColor = .clear
        secureTextField.backgroundColor = .clear
        secureTextField.borderStyle = .none
        secureTextField.isSecureTextEntry = true
        secureTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secureTextField)

        NSLayoutConstraint.activate([
            secureTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureTextField.trailingAnchor.constraint(equalTo: trailingAnchor),
            secureTextField.topAnchor.constraint(equalTo: topAnchor),
            secureTextField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let protectedView = secureTextField.subviews.first ?? secureTextField
        secureContentView = protectedView

        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        protectedView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: protectedView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: protectedView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: protectedView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: protectedView.bottomAnchor),
        ])
    }
}
