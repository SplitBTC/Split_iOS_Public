//
//  ReceiveInvoiceView.swift
//  Split
//
//  Shows a QR code for a Lightning invoice and lets the user copy it.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct ReceiveInvoiceView: View {
    let info: ReceiveAmountView.ReceiveInvoiceInfo
    /// Called when the user taps the X to leave the entire receive flow
    /// and return to the main customer index view.
    let onExitFlow: () -> Void

    private let context = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button(action: {
                        onExitFlow()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Receive Bitcoin")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.top, 8)

                if let qr = qrImage {
                    qr
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.top, 8)
                } else {
                    Text("Unable to generate QR code.")
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Amount")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Spacer()
                        Text(amountUsdText)
                            .foregroundColor(.white)
                            .font(.body)
                    }

                    HStack {
                        Text("Sats")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Spacer()
                        Text(amountSatsText)
                            .foregroundColor(.white)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lightning Invoice")
                            .foregroundColor(.gray)
                            .font(.caption)

                        ScrollView(.vertical, showsIndicators: true) {
                            Text(info.invoice)
                                .font(.footnote)
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(maxHeight: 120)
                        .background(Color.splitInputSurfaceSecondary)
                        .cornerRadius(12)
                    }

                }
                .padding()
                .background(Color.splitInputSurface)
                .cornerRadius(16)

                Spacer()

                Button(action: copyInvoice) {
                    HStack {
                        Spacer()
                        Text("Copy Invoice")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(18)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var amountUsdText: String {
        guard let amountUsd = info.amountUsd else {
            return "Payer chooses"
        }

        return String(format: "$%.2f", amountUsd)
    }

    private var amountSatsText: String {
        guard let amountSats = info.amountSats else {
            return "Payer chooses"
        }

        return formatSats(amountSats)
    }

    // MARK: - QR Code

    private var qrImage: Image? {
        let data = Data(info.invoice.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")

        guard let outputImage = qrFilter.outputImage else { return nil }

        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            return Image(uiImage: uiImage)
        }

        return nil
    }

    // MARK: - Actions

    private func copyInvoice() {
        UIPasteboard.general.string = info.invoice
    }

    private func formatSats(_ sats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
        return "\(formatted) sats"
    }
}
