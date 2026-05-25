//  LNQRSheet.swift
//  Split Rewards
//
//  Created by TeeVee on 3/13/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

private let splitBlue = Color.splitBrandBlue

struct IdentityShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let lightningAddress: String
    let suggestedContactName: String
    let paymentQRString: String
    let contactQRString: String

    @State private var selectedMode: ShareMode = .payment
    @State private var sharePayload: IdentityShareSharePayload?
    private enum ShareMode: String, CaseIterable, Identifiable {
        case payment = "Payment"
        case splitContact = "Add Contact"

        var id: String { rawValue }
    }

    private var activeQRString: String {
        selectedMode == .splitContact ? contactQRString : paymentQRString
    }

    private var activePrimaryText: String {
        selectedMode == .splitContact ? suggestedContactName : lightningAddress
    }

    private var activeSecondaryText: String {
        selectedMode == .splitContact ? lightningAddress : "LNURL Pay"
    }

    private var copyButtonTitle: String {
        "Copy"
    }

    private var shareButtonTitle: String {
        "Share"
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack {
                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    shareModeToggle

                    VStack(spacing: 16) {
                        QRCodeCard(qrString: activeQRString)

                        VStack(spacing: 6) {
                            Text(activePrimaryText)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .truncationMode(.middle)

                            Text(activeSecondaryText)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 24)
                    }

                    HStack(spacing: 12) {
                        Button(action: shareActiveCard) {
                            Text(shareButtonTitle)
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.white)
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: copyActiveCard) {
                            Text(copyButtonTitle)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(splitBlue)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
    }

    private func shareActiveCard() {
        let image = renderedShareImage()
        if let fileURL = image.writePNGToTemporaryFile(prefix: "split-identity") {
            sharePayload = IdentityShareSharePayload(items: [fileURL])
        } else {
            sharePayload = IdentityShareSharePayload(items: [image])
        }
    }

    private func copyActiveCard() {
        UIPasteboard.general.image = renderedShareImage()
    }

    private func renderedShareImage() -> UIImage {
        IdentityShareExportCard(
            qrString: activeQRString,
            primaryText: activePrimaryText,
            secondaryText: activeSecondaryText
        )
        .frame(width: 320, height: 430)
        .renderAsImage(size: CGSize(width: 320, height: 430))
    }

    private var shareModeToggle: some View {
        HStack(spacing: 8) {
            ForEach(ShareMode.allCases) { mode in
                Button(action: {
                    selectedMode = mode
                }) {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selectedMode == mode ? Color.splitBrandPink : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }
}

private struct IdentityShareExportCard: View {
    let qrString: String
    let primaryText: String
    let secondaryText: String

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 18) {
                QRCodeCard(qrString: qrString, size: 220, padding: 18)

                VStack(spacing: 8) {
                    Text(primaryText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .truncationMode(.middle)

                    Text(secondaryText)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }
}

private struct QRCodeCard: View {
    let qrString: String
    var size: CGFloat = 220
    var padding: CGFloat = 18

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 0) {
            if let image = generateQRCode(from: qrString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(padding)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("Unable to generate QR")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    )
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

private struct IdentityShareSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension UIImage {
    func writePNGToTemporaryFile(prefix: String) -> URL? {
        guard let data = pngData() else { return nil }
        let filename = "\(prefix)-\(UUID().uuidString).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}
