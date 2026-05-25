//
//  RequestPaymentMessageView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import SwiftUI

struct RequestPaymentMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @EnvironmentObject var authManager: AuthManager
    @FocusState private var amountFieldFocused: Bool

    let lightningAddress: String
    let onSent: () -> Void

    @State private var amountText = ""
    @State private var amountUnit: AmountUnit = .usd
    @State private var isSending = false
    @State private var errorMessage: String?

    private let background = Color.black
    private let fieldSurface = Color.splitInputSurface
    private let segmentedSurface = Color.white.opacity(0.08)

    private enum AmountUnit: String, CaseIterable {
        case usd = "USD"
        case sats = "sats"
    }

    private var parsedAmountSats: UInt64? {
        let cleaned = normalizedInputText

        switch amountUnit {
        case .sats:
            guard let sats = UInt64(cleaned), sats > 0 else { return nil }
            return sats
        case .usd:
            guard let usd = Double(cleaned),
                  usd > 0,
                  let rate = walletManager.btcUsdRate,
                  rate > 0 else {
                return nil
            }

            let satsDouble = (usd / rate) * 100_000_000.0
            guard satsDouble.isFinite, satsDouble > 0 else { return nil }
            return UInt64(max(1, Int64(satsDouble.rounded())))
        }
    }

    private var convertedValueText: String {
        guard let parsedAmountSats else {
            switch amountUnit {
            case .usd:
                return walletManager.btcUsdRate == nil
                    ? "BTC/USD rate unavailable right now."
                    : "We’ll convert this to sats for the invoice."
            case .sats:
                return "Enter the amount you want to request."
            }
        }

        switch amountUnit {
        case .usd:
            return "\(MessagePayloadCodec.formattedSats(parsedAmountSats)) sats"
        case .sats:
            guard let rate = walletManager.btcUsdRate, rate > 0 else {
                return "USD estimate unavailable right now."
            }
            let usd = (Double(parsedAmountSats) / 100_000_000.0) * rate
            return formatUSDDisplay(usd)
        }
    }

    private var amountTitle: String {
        switch amountUnit {
        case .usd:
            return "Amount (USD)"
        case .sats:
            return "Amount (sats)"
        }
    }

    private var amountPlaceholder: String {
        switch amountUnit {
        case .usd:
            return "5.00"
        case .sats:
            return "1000"
        }
    }

    private var normalizedInputText: String {
        amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
    }

    private var canSend: Bool {
        guard let parsedAmountSats else { return false }
        return parsedAmountSats > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        amountFieldFocused = false
                    }

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Request")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)

                        Text("Create a Lightning invoice and send it into this thread as a payment card.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.64))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(amountTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.78))

                        Picker("Amount Unit", selection: $amountUnit) {
                            ForEach(AmountUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(segmentedSurface)
                        )

                        TextField(amountPlaceholder, text: $amountText)
                            .keyboardType(amountUnit == .usd ? .decimalPad : .numberPad)
                            .focused($amountFieldFocused)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(fieldSurface)
                            )

                        Text(convertedValueText)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.66))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("To")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.54))

                        Text(lightningAddress)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        Button(action: {
                            guard !isSending, canSend else { return }
                            Task {
                                await sendRequest()
                            }
                        }) {
                            HStack {
                                Spacer()
                                if isSending {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send Request")
                                        .font(.headline.weight(.semibold))
                                        .foregroundColor(.white)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(canSend ? Color.splitBrandPink : Color.white.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend || isSending)

                        Button(action: { dismiss() }) {
                            HStack {
                                Spacer()
                                Text("Cancel")
                                    .font(.headline.weight(.medium))
                                    .foregroundColor(.white.opacity(0.78))
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.white.opacity(0.07))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: amountUnit) { oldUnit, newUnit in
            syncDisplayForSelectedUnit(from: oldUnit, to: newUnit)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    amountFieldFocused = false
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    @MainActor
    private func sendRequest() async {
        guard let amountSats = parsedAmountSats, amountSats > 0 else { return }

        isSending = true
        errorMessage = nil

        do {
            let requesterAddress = try await walletManager.fetchLightningAddress()?.lightningAddress
            let description = requesterAddress ?? "Split payment request"

            let invoice = try await createInvoice(
                description: description,
                amountSats: amountSats
            )

            _ = try await MessagingSendCoordinator.sendPaymentRequest(
                lightningAddress: lightningAddress,
                payload: PaymentRequestMessagePayload(
                    invoice: invoice,
                    amountSats: amountSats,
                    requesterLightningAddress: requesterAddress,
                    note: nil
                ),
                authManager: authManager,
                walletManager: walletManager
            )

            onSent()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    private func createInvoice(
        description: String,
        amountSats: UInt64
    ) async throws -> String {
        if activeSpendWalletStore.isLndActive {
            if !lndWalletManager.isConnected {
                try await lndWalletManager.restoreActiveNode()
            }

            let response = try await lndWalletManager.createInvoice(
                amountSats: Int64(amountSats),
                memo: description
            )
            return response.paymentRequest
        }

        if activeSpendWalletStore.isNWCActive {
            if !nwcWalletManager.isConnected {
                try await nwcWalletManager.restoreActiveWallet()
            }

            guard nwcWalletManager.connectedWallet?.capabilities?.supportsInvoices != false else {
                throw NWCWalletError.unsupportedMethod("make_invoice")
            }

            let response = try await nwcWalletManager.createInvoice(
                amountSats: Int64(amountSats),
                memo: description
            )

            guard let invoice = response.invoice?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !invoice.isEmpty else {
                throw NWCWalletError.invalidRelayResponse
            }

            return invoice
        }

        if activeSpendWalletStore.isCoreLightningActive {
            if !coreLightningWalletManager.isConnected {
                try await coreLightningWalletManager.restoreActiveNode()
            }

            let response = try await coreLightningWalletManager.createInvoice(
                amountSats: Int64(amountSats),
                memo: description
            )
            return response.bolt11
        }

        if activeSpendWalletStore.isEclairActive {
            if !eclairWalletManager.isConnected {
                try await eclairWalletManager.restoreActiveNode()
            }

            let response = try await eclairWalletManager.createInvoice(
                amountSats: Int64(amountSats),
                memo: description
            )
            return response.serialized
        }

        guard let invoice = await walletManager.generateBolt11Invoice(
            description: description,
            amountSats: amountSats
        ) else {
            throw NSError(
                domain: "RequestPaymentMessageView",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: walletManager.lastErrorMessage ?? "Failed to create invoice."
                ]
            )
        }

        return invoice
    }

    private func syncDisplayForSelectedUnit(from oldUnit: AmountUnit, to newUnit: AmountUnit) {
        let sourceText = amountText
        guard let currentSats = parsedAmountSats(for: oldUnit, inputText: sourceText) else { return }

        switch newUnit {
        case .usd:
            guard let rate = walletManager.btcUsdRate, rate > 0 else { return }
            let usd = (Double(currentSats) / 100_000_000.0) * rate
            amountText = formatUSDInput(usd)
        case .sats:
            amountText = "\(currentSats)"
        }
    }

    private func parsedAmountSats(for unit: AmountUnit, inputText: String) -> UInt64? {
        let cleaned = inputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        switch unit {
        case .sats:
            guard let sats = UInt64(cleaned), sats > 0 else { return nil }
            return sats
        case .usd:
            guard let usd = Double(cleaned),
                  usd > 0,
                  let rate = walletManager.btcUsdRate,
                  rate > 0 else {
                return nil
            }

            let satsDouble = (usd / rate) * 100_000_000.0
            guard satsDouble.isFinite, satsDouble > 0 else { return nil }
            return UInt64(max(1, Int64(satsDouble.rounded())))
        }
    }

    private func formatUSDInput(_ usd: Double) -> String {
        String(format: "%.2f", usd)
    }

    private func formatUSDDisplay(_ usd: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: usd)) ?? "$\(formatUSDInput(usd))"
    }
}
