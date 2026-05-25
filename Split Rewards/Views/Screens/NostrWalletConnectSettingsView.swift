//
//  NostrWalletConnectSettingsView.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import SwiftUI

struct NostrWalletConnectSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nwcWalletManager: NWCWalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore

    let showsDismissButton: Bool
    let showsSavedWallets: Bool
    let onWalletAdded: (() -> Void)?

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var connectionString = ""
    @State private var walletName = ""
    @State private var isConnecting = false
    @State private var isRefreshing = false
    @State private var isScanningQRCode = false
    @State private var statusMessage: String?
    @State private var renamingWallet: NWCWalletCredentials?
    @State private var renameText = ""
    @State private var connectedWalletConfirmation: NWCWalletCredentials?

    private let limitedFeatureSupportTitle = "Connected with limited feature support"
    private let limitedFeatureSupportMessage = "This wallet does not offer a full range of features via NWC. Real time update support may be limited based on this wallet's NWC configuration."

    init(showsDismissButton: Bool = false, showsSavedWallets: Bool = true, onWalletAdded: (() -> Void)? = nil) {
        self.showsDismissButton = showsDismissButton
        self.showsSavedWallets = showsSavedWallets
        self.onWalletAdded = onWalletAdded
    }

    private var hasStoredWallet: Bool {
        !nwcWalletManager.storedWallets().isEmpty
    }

    private var activeWallet: NWCWalletCredentials? {
        nwcWalletManager.connectedWallet ?? NWCCredentialStore.shared.activeWallet()
    }

    private var hasLimitedFeatureSupport: Bool {
        guard let capabilities = activeWallet?.capabilities else {
            return false
        }

        return !capabilities.supportsSplitRequiredCapabilities
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            if isScanningQRCode {
                scannerContent
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if showsSavedWallets && hasStoredWallet {
                            connectedContent
                        }

                        if let connectedWalletConfirmation, !showsSavedWallets {
                            successContent(for: connectedWalletConfirmation)
                        } else {
                            connectContent
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white.opacity(0.70))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("NWC Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .sheet(item: $renamingWallet) { wallet in
            RenameExternalWalletSheet(
                title: "Rename Wallet",
                initialName: wallet.displayName,
                text: $renameText,
                onSave: {
                    renameWallet(wallet)
                }
            )
            .presentationDetents([.fraction(0.32)])
            .presentationDragIndicator(.visible)
        }
        .task {
            if showsSavedWallets {
                await restoreWalletIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NWC Wallet")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text(showsSavedWallets && hasStoredWallet ? "Manage your connection" : "Connect a Lightning wallet or node")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            nwcCompatibilityCopy

            walletNameField

            Button(action: openQRScanner) {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.headline)

                    Text("Scan QR Code")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(blue)
                )
            }
            .disabled(isConnecting)

            Text("NWC Connection")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            TextField("nostr+walletconnect://", text: $connectionString, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .lineLimit(4...8)
                .foregroundColor(.white)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )

            Button(action: {
                Task { await connectWallet() }
            }) {
                HStack(spacing: 10) {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        NWCSymbol()
                            .frame(width: 20, height: 20)
                    }

                    Text(isConnecting ? connectingStatusText : "Connect Wallet")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canConnect ? blue : Color.white.opacity(0.14))
                )
            }
            .disabled(!canConnect)
        }
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var nwcCompatibilityCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.headline)
                    .foregroundColor(blue)

                Text("Before You Connect")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            Text("Split will keep your Spark wallet as your account identity. NWC is used only as an optional spending wallet.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                compatibilityRow(
                    icon: "link",
                    text: "Use a nostr+walletconnect:// string or QR from a wallet, node, or hub that supports NWC. Onion relays are routed through Tor."
                )
                compatibilityRow(
                    icon: "lock.shield.fill",
                    text: "The NWC secret stays in this device's keychain."
                )
                compatibilityRow(
                    icon: "checkmark.seal.fill",
                    text: "Split checks the wallet's advertised NWC features and enables supported payment flows."
                )
            }
        }
    }

    private func successContent(for wallet: NWCWalletCredentials) -> some View {
        let capabilities = wallet.capabilities
        let limitedSupport = capabilities.map { !$0.supportsSplitRequiredCapabilities } ?? false

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text(limitedSupport ? limitedFeatureSupportTitle : "NWC wallet connected")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(wallet.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.64))
                }
            }

            detailRow("Wallet Pubkey", value: abbreviated(wallet.walletPubkey))
            detailRow("Relay", value: wallet.primaryRelayHost)
            detailRow("Connection", value: wallet.usesTor ? "Tor" : "Direct")
            detailRow("Encryption", value: capabilities?.preferredEncryptionMode.rawValue.uppercased() ?? "Not advertised")

            if limitedSupport {
                limitedFeatureSupportNotice
            }

            Button {
                onWalletAdded?()
            } label: {
                Text("Done")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(blue))
            }

            Button {
                connectedWalletConfirmation = nil
                statusMessage = nil
            } label: {
                Text("Connect another")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var walletNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Name")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            TextField("Required", text: $walletName)
                .textInputAutocapitalization(.words)
                .foregroundColor(.white)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private func compatibilityRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.78))
                .frame(width: 18, height: 18)

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scannerContent: some View {
        ZStack(alignment: .topLeading) {
            QRCodeScannerView(preferredZoomFactor: 1.6, onCodeScanned: handleScannedCode)
                .ignoresSafeArea()

            Button(action: closeQRScanner) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close scanner")
            .padding(.top, 14)
            .padding(.leading, 16)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Saved Wallets")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            ForEach(nwcWalletManager.storedWallets()) { wallet in
                savedWalletRow(wallet)
            }
        }
    }

    private func savedWalletRow(_ wallet: NWCWalletCredentials) -> some View {
        let isActive = activeWallet?.id == wallet.id
        let capabilities = wallet.capabilities
        let limitedSupport = capabilities.map { !$0.supportsSplitRequiredCapabilities } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    NWCSymbol()
                        .frame(width: 32, height: 32)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(wallet.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(isActive ? (limitedSupport ? limitedFeatureSupportTitle : statusText) : "Saved on this device")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(pink)
                }
            }

            detailRow("Wallet Pubkey", value: abbreviated(wallet.walletPubkey))
            detailRow("Relay", value: wallet.primaryRelayHost)
            detailRow("Connection", value: wallet.usesTor ? "Tor" : "Direct")
            detailRow("Encryption", value: capabilities?.preferredEncryptionMode.rawValue.uppercased() ?? "Not advertised")

            if limitedSupport {
                limitedFeatureSupportNotice
            }

            HStack(spacing: 10) {
                Button {
                    Task { await selectWallet(wallet) }
                } label: {
                    Text(isActive ? "Selected" : "Use")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12).fill(blue.opacity(isActive ? 0.45 : 1)))
                }
                .disabled(isActive)

                Button {
                    renameText = wallet.displayName
                    renamingWallet = wallet
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
                }

                Button(role: .destructive) {
                    forgetWallet(wallet)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(pink))
                }
            }
        }
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var limitedFeatureSupportNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.yellow)

                Text(limitedFeatureSupportTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            Text(limitedFeatureSupportMessage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var walletSummaryCard: some View {
        let wallet = activeWallet
        let capabilities = wallet?.capabilities

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    NWCSymbol()
                        .frame(width: 32, height: 32)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(wallet?.displayName ?? "NWC Wallet")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            detailRow("Wallet Pubkey", value: abbreviated(wallet?.walletPubkey))
            detailRow("Relay", value: wallet?.primaryRelayHost ?? "Not available")
            detailRow("Connection", value: wallet?.usesTor == true ? "Tor" : "Direct")
            detailRow("Encryption", value: capabilities?.preferredEncryptionMode.rawValue.uppercased() ?? "Not advertised")
        }
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var canConnect: Bool {
        !isConnecting
        && !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !connectionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        switch nwcWalletManager.state {
        case .ready:
            return hasLimitedFeatureSupport ? limitedFeatureSupportTitle : "Connected"
        case .connecting:
            return "Connecting"
        case .error:
            return "Needs attention"
        case .disconnected:
            return "Saved on this device"
        }
    }

    private var connectingStatusText: String {
        usesTor(rawConnectionString: connectionString) ? "Starting Tor" : "Connecting"
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.58))

            Spacer(minLength: 16)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private func restoreWalletIfNeeded() async {
        guard NWCCredentialStore.shared.activeWallet() != nil else { return }

        do {
            try await nwcWalletManager.restoreActiveWallet()
            statusMessage = hasLimitedFeatureSupport ? limitedFeatureSupportMessage : nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connectWallet() async {
        await connectWallet(using: connectionString)
    }

    private func connectWallet(using rawConnectionString: String) async {
        let normalized = rawConnectionString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            statusMessage = "Enter an NWC connection string."
            return
        }

        let label = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            statusMessage = "Name this wallet before connecting."
            return
        }

        isConnecting = true
        statusMessage = usesTor(rawConnectionString: normalized) ? "Starting Tor..." : "Checking NWC wallet..."

        do {
            let wallet = try await nwcWalletManager.connect(nwcConnectionString: normalized, label: label)
            _ = try? await nwcWalletManager.refreshBalance()
            statusMessage = "Saving wallet..."
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .nwc, id: wallet.id)
            connectionString = ""
            walletName = ""
            connectedWalletConfirmation = wallet
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func refreshConnection() async {
        isRefreshing = true
        statusMessage = nil

        do {
            _ = try await nwcWalletManager.refreshWalletInfo()
            _ = try? await nwcWalletManager.refreshBalance()
            statusMessage = hasLimitedFeatureSupport ? limitedFeatureSupportTitle : "Connection refreshed"
        } catch {
            statusMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    private func forgetWallet(_ wallet: NWCWalletCredentials) {
        nwcWalletManager.forgetWallet(id: wallet.id)
        activeSpendWalletStore.reconcileWithStoredWallets()
        statusMessage = nil
    }

    private func selectWallet(_ wallet: NWCWalletCredentials) async {
        do {
            try await nwcWalletManager.setActiveStoredWallet(id: wallet.id)
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .nwc, id: wallet.id)
            _ = try? await nwcWalletManager.refreshBalance()
            statusMessage = "Selected \(wallet.displayName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func renameWallet(_ wallet: NWCWalletCredentials) {
        nwcWalletManager.renameWallet(id: wallet.id, label: renameText)
        renamingWallet = nil
        renameText = ""
    }

    private func openQRScanner() {
        statusMessage = nil
        isScanningQRCode = true
    }

    private func closeQRScanner() {
        isScanningQRCode = false
    }

    private func handleScannedCode(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.lowercased().hasPrefix("nostr+walletconnect://") else {
            isScanningQRCode = false
            statusMessage = "Scan an NWC QR code from a Lightning wallet or node."
            return
        }

        connectionString = normalized
        isScanningQRCode = false

        if walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = "Name this wallet, then connect."
        } else {
            Task {
                await connectWallet(using: normalized)
            }
        }
    }

    private func abbreviated(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "Not available"
        }

        guard value.count > 14 else {
            return value
        }

        let prefix = value.prefix(8)
        let suffix = value.suffix(6)
        return "\(prefix)...\(suffix)"
    }

    private func usesTor(rawConnectionString: String) -> Bool {
        (try? NWCConnectParser.parse(rawConnectionString).relayURLs)
            .map { relays in
                relays.contains { relay in
                    URLComponents(string: relay)?
                        .host?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .hasSuffix(".onion") == true
                }
            } ?? false
    }
}

#Preview {
    NavigationStack {
        NostrWalletConnectSettingsView()
            .environmentObject(NWCWalletManager())
            .environmentObject(ActiveSpendWalletStore())
    }
}
