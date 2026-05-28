//  ReceiveAmountView.swift
//  Split
//
//  Enter an amount in USD or sats and generate a Lightning invoice.
//
import SwiftUI
import UIKit

struct ReceiveAmountView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject private var lndWalletManager: LNDWalletManager
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var coreLightningWalletManager: CoreLightningWalletManager
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @Environment(\.dismiss) private var dismiss

    @State private var usdAmountText: String = ""
    @State private var satsAmountText: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var invoiceInfo: ReceiveInvoiceInfo?
    @State private var showInvoiceSheet: Bool = false
    @State private var isAmountlessInvoice: Bool = false

    // ✅ Description the user can enter (included in BOLT11 invoice)
    @State private var descriptionText: String = ""

    // Track which field user is editing so we only convert in that direction
    @FocusState private var focusedField: Field?
    @State private var isProgrammaticUpdate: Bool = false

    private enum Field {
        case usd, sats, description
    }

    /// Simple helper used only on the receive side UI.
    struct ReceiveInvoiceInfo {
        let invoice: String
        let amountUsd: Double?
        let amountSats: UInt64?
    }

    // MARK: - Derived values

    private var usdAmount: Double? {
        Double(cleanNumeric(usdAmountText))
    }

    private var satsAmount: UInt64? {
        let cleaned = cleanNumeric(satsAmountText)
        guard let sats = UInt64(cleaned), sats > 0 else { return nil }
        return sats
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.97)
                .ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                    // Top bar
                    HStack {
                        Button(action: {
                            dismissKeyboard()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }

                        Spacer()

                        Text("Request Bitcoin")
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        Color.clear
                            .frame(width: 32, height: 32)
                    }
                    .padding(.top, 8)

                    // Amount entry + sats display
                    VStack(alignment: .leading, spacing: 16) {
                        if !isAmountlessInvoice {
                            Text("Amount in USD")
                                .font(.caption)
                                .foregroundColor(.gray)

                            HStack(spacing: 8) {
                                Text("$")
                                    .font(.title2)
                                    .foregroundColor(.white)

                                TextField("0.00", text: $usdAmountText)
                                    .keyboardType(.decimalPad)
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .focused($focusedField, equals: .usd)
                                    .onChange(of: usdAmountText) {
                                        guard focusedField == .usd else { return }
                                        guard !isProgrammaticUpdate else { return }
                                        Task { await updateSatsFromUsd() }
                                    }
                            }
                            .padding()
                            .background(Color.splitInputSurface)
                            .cornerRadius(14)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = .usd
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sats amount")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                TextField("1000", text: $satsAmountText)
                                    .keyboardType(.numberPad)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.splitInputSurface)
                                    .cornerRadius(14)
                                    .focused($focusedField, equals: .sats)
                                    .onChange(of: satsAmountText) {
                                        let sanitized = sanitizeSatsInput(satsAmountText)
                                        if sanitized != satsAmountText {
                                            satsAmountText = sanitized
                                            return
                                        }
                                        guard focusedField == .sats else { return }
                                        guard !isProgrammaticUpdate else { return }
                                        Task { await updateUsdFromSats() }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        focusedField = .sats
                                    }

                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                        }

                        // ✅ Optional invoice description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description (optional)")
                                .font(.caption)
                                .foregroundColor(.gray)

                            TextField("Optional", text: $descriptionText, axis: .vertical)
                                .lineLimit(1...3)
                                .textInputAutocapitalization(.sentences)
                                .disableAutocorrection(false)
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.splitInputSurface)
                                .cornerRadius(14)
                                .focused($focusedField, equals: .description)
                                .submitLabel(.done)
                                .onSubmit { dismissKeyboard() }
                                .onChange(of: descriptionText) {
                                    // Soft limit to keep invoices and UI tidy
                                    if descriptionText.count > 80 {
                                        descriptionText = String(descriptionText.prefix(80))
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    focusedField = .description
                                }

                            Text("Keep it short. This text is embedded in the invoice and may be visible to the sender.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                                .background(Color.splitInputSurfaceSecondary)
                                .cornerRadius(14)
                        }

                        Button {
                            isAmountlessInvoice.toggle()
                            if isAmountlessInvoice {
                                dismissKeyboard()
                                usdAmountText = ""
                                satsAmountText = ""
                                errorMessage = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text("Create a blank Lightning invoice")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)

                                Spacer()

                                ZStack {
                                    Circle()
                                        .fill(isAmountlessInvoice ? Color.splitBrandBlue : Color.clear)
                                    Circle()
                                        .stroke(
                                            isAmountlessInvoice ? Color.splitBrandBlue : Color.white.opacity(0.45),
                                            lineWidth: 2
                                        )
                                    if isAmountlessInvoice {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .frame(width: 24, height: 24)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.splitInputSurface)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Spacer(minLength: 24)

                    // Confirm button + helper text
                    VStack(spacing: 8) {
                        Button(action: generateInvoice) {
                            HStack {
                                Spacer()
                                if isGenerating {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Confirm")
                                        .font(.headline)
                                }
                                Spacer()
                            }
                            .padding()
                            .background(Color.white.opacity(isGenerating ? 0.3 : 1.0))
                            .foregroundColor(.black)
                            .cornerRadius(18)
                        }
                        .disabled(!canGenerateInvoice)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if isGenerating {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { } // swallow taps while generating
            }
        }
        .fullScreenCover(isPresented: $showInvoiceSheet, onDismiss: {
            invoiceInfo = nil
        }) {
            if let info = invoiceInfo {
                ReceiveInvoiceView(
                    info: info,
                    onExitFlow: {
                        showInvoiceSheet = false
                        dismiss()
                    }
                )
            } else {
                Text("No invoice available.")
                    .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
                .font(.headline)
            }
        }
    }

    // MARK: - Helpers

    private var canGenerateInvoice: Bool {
        if isAmountlessInvoice {
            return !isGenerating
        }

        guard let usd = usdAmount, usd > 0 else { return false }
        guard let sats = satsAmount, sats > 0 else { return false }
        return !isGenerating
    }

    /// Normalizes numeric entry by removing commas/spaces.
    private func cleanNumeric(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func updateSatsFromUsd() async {
        guard let usd = usdAmount, usd > 0 else {
            isProgrammaticUpdate = true
            satsAmountText = ""
            isProgrammaticUpdate = false
            return
        }

        if let btc = await walletManager.convertUsdToBtc(usdAmount: usd) {
            let sats = UInt64(max(1, Int64((btc * 100_000_000.0).rounded())))
            isProgrammaticUpdate = true
            satsAmountText = "\(sats)"
            isProgrammaticUpdate = false

            if let error = errorMessage,
               error.contains("rate") || error.contains("BTC") {
                errorMessage = nil
            }
        } else {
            isProgrammaticUpdate = true
            satsAmountText = ""
            isProgrammaticUpdate = false
            errorMessage = "Unable to load the current BTC rate. Please try again."
        }
    }

    /// Uses the same rate source as USD→sats by inverting convertUsdToBtc(1.0).
    @MainActor
    private func updateUsdFromSats() async {
        guard let sats = satsAmount, sats > 0 else {
            isProgrammaticUpdate = true
            usdAmountText = ""
            isProgrammaticUpdate = false
            return
        }

        // Get BTC-per-USD at current rate (usd=1). Then invert to USD-per-BTC.
        guard let btcPerUsd = await walletManager.convertUsdToBtc(usdAmount: 1.0),
              btcPerUsd > 0 else {
            errorMessage = "Unable to load the current BTC rate. Please try again."
            return
        }

        let btc = Double(sats) / 100_000_000.0
        let usd = btc / btcPerUsd

        isProgrammaticUpdate = true
        usdAmountText = String(format: "%.2f", usd)
        isProgrammaticUpdate = false

        if let error = errorMessage,
           error.contains("rate") || error.contains("BTC") {
            errorMessage = nil
        }
    }

    private func sanitizeSatsInput(_ raw: String) -> String {
        let digits = raw.filter { $0.isWholeNumber }
        return String(digits.drop(while: { $0 == "0" }))
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func generateInvoice() {
        errorMessage = nil
        dismissKeyboard()

        let requestedUsd: Double?
        let requestedSats: UInt64?

        if isAmountlessInvoice {
            requestedUsd = nil
            requestedSats = nil
        } else {
            guard let usd = usdAmount, usd > 0 else {
                errorMessage = "Enter a valid USD amount."
                return
            }

            guard let sats = satsAmount, sats > 0 else {
                errorMessage = "Enter a valid sats amount."
                return
            }

            requestedUsd = usd
            requestedSats = sats
        }

        if let requestedSats, int64Sats(requestedSats) == nil {
            errorMessage = "Enter a smaller sats amount."
            return
        }

        isGenerating = true

        Task {
            let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? "Split payment" : descriptionText

            if activeSpendWalletStore.isLndActive {
                do {
                    if !lndWalletManager.isConnected {
                        try await lndWalletManager.restoreActiveNode()
                    }

                    let response = try await lndWalletManager.createInvoice(
                        amountSats: int64Sats(requestedSats),
                        memo: description
                    )

                    await MainActor.run {
                        self.invoiceInfo = ReceiveInvoiceInfo(
                            invoice: response.paymentRequest,
                            amountUsd: requestedUsd,
                            amountSats: requestedSats
                        )
                        self.isGenerating = false
                        self.showInvoiceSheet = true
                    }
                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.errorMessage = error.localizedDescription
                    }
                }

                return
            }

            if activeSpendWalletStore.isNWCActive {
                do {
                    if !nwcWalletManager.isConnected {
                        try await nwcWalletManager.restoreActiveWallet()
                    }

                    guard nwcWalletManager.connectedWallet?.capabilities?.supportsInvoices != false else {
                        throw NWCWalletError.unsupportedMethod("make_invoice")
                    }

                    let response = try await nwcWalletManager.createInvoice(
                        amountSats: int64Sats(requestedSats),
                        memo: description
                    )

                    guard let invoice = response.invoice?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !invoice.isEmpty else {
                        throw NWCWalletError.invalidRelayResponse
                    }

                    await MainActor.run {
                        self.invoiceInfo = ReceiveInvoiceInfo(
                            invoice: invoice,
                            amountUsd: requestedUsd,
                            amountSats: requestedSats
                        )
                        self.isGenerating = false
                        self.showInvoiceSheet = true
                    }
                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.errorMessage = error.localizedDescription
                    }
                }

                return
            }

            if activeSpendWalletStore.isCoreLightningActive {
                do {
                    if !coreLightningWalletManager.isConnected {
                        try await coreLightningWalletManager.restoreActiveNode()
                    }

                    let response = try await coreLightningWalletManager.createInvoice(
                        amountSats: int64Sats(requestedSats),
                        memo: description
                    )

                    await MainActor.run {
                        self.invoiceInfo = ReceiveInvoiceInfo(
                            invoice: response.bolt11,
                            amountUsd: requestedUsd,
                            amountSats: requestedSats
                        )
                        self.isGenerating = false
                        self.showInvoiceSheet = true
                    }
                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.errorMessage = error.localizedDescription
                    }
                }

                return
            }

            if activeSpendWalletStore.isEclairActive {
                do {
                    if !eclairWalletManager.isConnected {
                        try await eclairWalletManager.restoreActiveNode()
                    }

                    let response = try await eclairWalletManager.createInvoice(
                        amountSats: int64Sats(requestedSats),
                        memo: description
                    )

                    await MainActor.run {
                        self.invoiceInfo = ReceiveInvoiceInfo(
                            invoice: response.serialized,
                            amountUsd: requestedUsd,
                            amountSats: requestedSats
                        )
                        self.isGenerating = false
                        self.showInvoiceSheet = true
                    }
                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.errorMessage = error.localizedDescription
                    }
                }

                return
            }

            if activeSpendWalletStore.isSparkSubwalletActive {
                do {
                    if !sparkSubwalletManager.isConnected {
                        try await sparkSubwalletManager.restoreWalletIfNeeded()
                    }

                    let invoice = try await sparkSubwalletManager.generateBolt11Invoice(
                        description: description,
                        amountSats: requestedSats
                    )

                    await MainActor.run {
                        self.invoiceInfo = ReceiveInvoiceInfo(
                            invoice: invoice,
                            amountUsd: requestedUsd,
                            amountSats: requestedSats
                        )
                        self.isGenerating = false
                        self.showInvoiceSheet = true
                    }
                } catch {
                    await MainActor.run {
                        self.isGenerating = false
                        self.errorMessage = error.localizedDescription
                    }
                }

                return
            }

            if let invoice = await walletManager.generateBolt11Invoice(description: description, amountSats: requestedSats) {
                await MainActor.run {
                    self.invoiceInfo = ReceiveInvoiceInfo(invoice: invoice, amountUsd: requestedUsd, amountSats: requestedSats)
                    self.isGenerating = false
                    self.showInvoiceSheet = true
                }
            } else {
                await MainActor.run {
                    self.isGenerating = false
                    self.errorMessage = walletManager.lastErrorMessage ?? "Failed to generate invoice."
                }
            }
        }
    }

    private func int64Sats(_ sats: UInt64?) -> Int64? {
        guard let sats else { return nil }
        guard sats <= UInt64(Int64.max) else { return nil }
        return Int64(sats)
    }
}
