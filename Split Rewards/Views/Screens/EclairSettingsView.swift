//
//  EclairSettingsView.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import SwiftUI

struct EclairSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eclairWalletManager: EclairWalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore

    let showsDismissButton: Bool
    let showsSavedWallets: Bool
    let onWalletAdded: (() -> Void)?

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var walletName = ""
    @State private var scheme = "http"
    @State private var host = ""
    @State private var port = "8080"
    @State private var apiPassword = ""
    @State private var isConnecting = false
    @State private var isScanningQRCode = false
    @State private var statusMessage: String?
    @State private var renamingNode: EclairNodeCredentials?
    @State private var renameText = ""
    @State private var connectedNodeConfirmation: EclairNodeCredentials?

    init(showsDismissButton: Bool = false, showsSavedWallets: Bool = true, onWalletAdded: (() -> Void)? = nil) {
        self.showsDismissButton = showsDismissButton
        self.showsSavedWallets = showsSavedWallets
        self.onWalletAdded = onWalletAdded
    }

    private var hasStoredNode: Bool {
        !eclairWalletManager.storedNodes().isEmpty
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

                        if showsSavedWallets && hasStoredNode {
                            connectedContent
                        }

                        if let connectedNodeConfirmation, !showsSavedWallets {
                            successContent(for: connectedNodeConfirmation)
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
        .navigationTitle("Eclair")
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
        .sheet(item: $renamingNode) { node in
            RenameExternalWalletSheet(
                title: "Rename Wallet",
                initialName: node.displayName,
                text: $renameText,
                onSave: {
                    renameNode(node)
                }
            )
            .presentationDetents([.fraction(0.32)])
            .presentationDragIndicator(.visible)
        }
        .task {
            if showsSavedWallets {
                await restoreNodeIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Eclair")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text(showsSavedWallets && hasStoredNode ? "Manage your Eclair API connection" : "Connect an Eclair node to Split")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            compatibilityCopy

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
                .background(RoundedRectangle(cornerRadius: 14).fill(blue))
            }
            .disabled(isConnecting)

            HStack(spacing: 10) {
                Picker("Scheme", selection: $scheme) {
                    Text("http").tag("http")
                    Text("https").tag("https")
                }
                .pickerStyle(.segmented)

                TextField("8080", text: $port)
                    .keyboardType(.numberPad)
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(width: 92)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }

            TextField("Eclair host or .onion address", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .foregroundColor(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))

            SecureField("API password", text: $apiPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))

            Button(action: {
                Task { await connectNode() }
            }) {
                HStack(spacing: 10) {
                    if isConnecting {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.headline)
                    }

                    Text(isConnecting ? connectingStatusText : "Connect Node")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(canConnect ? blue : Color.white.opacity(0.14)))
            }
            .disabled(!canConnect)
        }
        .padding(16)
        .background(cardSurface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func successContent(for node: EclairNodeCredentials) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(pink)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Eclair node connected")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(node.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.64))
                }
            }

            detailRow("Node ID", value: abbreviated(node.nodeId))
            detailRow("Host", value: "\(node.scheme)://\(node.host):\(node.port)")
            detailRow("Connection", value: node.usesTor ? "Tor" : "Direct")

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
                connectedNodeConfirmation = nil
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
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var compatibilityCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.headline)
                    .foregroundColor(blue)

                Text("Before You Connect")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            Text("Split connects to Eclair through its HTTP API.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                compatibilityRow(
                    icon: "network",
                    text: "Use a private LAN or VPN hostname/IP, a .local hostname, a Tailscale .ts.net host, or a Tor .onion service."
                )
                compatibilityRow(
                    icon: "key.fill",
                    text: "Your Eclair API password stays in this device's keychain."
                )
                compatibilityRow(
                    icon: "checkmark.seal.fill",
                    text: "Split uses Eclair for node info, balance, invoices, payments, and history."
                )
            }
        }
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
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
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
            Text("Saved Nodes")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            ForEach(eclairWalletManager.storedNodes()) { node in
                savedNodeRow(node)
            }
        }
    }

    private func savedNodeRow(_ node: EclairNodeCredentials) -> some View {
        let isActive = (eclairWalletManager.connectedNode ?? EclairCredentialStore.shared.activeNode())?.id == node.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(blue)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(node.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(isActive ? statusText : "Saved on this device")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.60))
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(pink)
                }
            }

            detailRow("Node ID", value: abbreviated(node.nodeId))
            detailRow("Host", value: "\(node.scheme)://\(node.host):\(node.port)")
            detailRow("Connection", value: node.usesTor ? "Tor" : "Direct")

            HStack(spacing: 10) {
                Button {
                    Task { await selectNode(node) }
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
                    renameText = node.displayName
                    renamingNode = node
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10)))
                }

                Button(role: .destructive) {
                    forgetNode(node)
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
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var canConnect: Bool {
        !isConnecting
        && !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !apiPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusText: String {
        switch eclairWalletManager.state {
        case .ready:
            return "Connected"
        case .connecting:
            return connectingStatusText
        case .error:
            return "Needs attention"
        case .disconnected:
            return "Saved on this device"
        }
    }

    private var connectingStatusText: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".onion")
            ? "Starting Tor"
            : "Connecting"
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

    private func restoreNodeIfNeeded() async {
        guard EclairCredentialStore.shared.activeNode() != nil else { return }

        do {
            try await eclairWalletManager.restoreActiveNode()
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connectNode() async {
        let label = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            statusMessage = "Name this wallet before connecting."
            return
        }

        isConnecting = true
        statusMessage = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".onion")
            ? "Starting Tor..."
            : "Checking Eclair node..."

        do {
            let node = try await eclairWalletManager.connect(
                scheme: scheme,
                host: host,
                port: port,
                apiPassword: apiPassword,
                label: label
            )
            statusMessage = "Saving wallet..."
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .eclair, id: node.id)
            host = ""
            port = "8080"
            apiPassword = ""
            walletName = ""
            connectedNodeConfirmation = node
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func connectNode(using connectionString: String) async {
        let label = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            statusMessage = "Name this wallet before connecting."
            return
        }

        isConnecting = true
        statusMessage = usesTor(rawConnectionString: connectionString)
            ? "Starting Tor..."
            : "Checking Eclair node..."

        do {
            let node = try await eclairWalletManager.connect(
                connectionString: connectionString,
                label: label
            )
            statusMessage = "Saving wallet..."
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .eclair, id: node.id)
            host = ""
            port = "8080"
            apiPassword = ""
            walletName = ""
            connectedNodeConfirmation = node
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        isConnecting = false
    }

    private func forgetNode(_ node: EclairNodeCredentials) {
        eclairWalletManager.forgetNode(id: node.id)
        activeSpendWalletStore.reconcileWithStoredWallets()
        statusMessage = nil
    }

    private func selectNode(_ node: EclairNodeCredentials) async {
        do {
            try await eclairWalletManager.setActiveStoredNode(id: node.id)
            _ = activeSpendWalletStore.setExternalWalletActive(kind: .eclair, id: node.id)
            _ = try? await eclairWalletManager.refreshBalance()
            statusMessage = "Selected \(node.displayName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func renameNode(_ node: EclairNodeCredentials) {
        eclairWalletManager.renameNode(id: node.id, label: renameText)
        renamingNode = nil
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

        do {
            let parsed = try EclairConnectParser.parse(
                connectionString: normalized,
                label: walletName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            )
            scheme = parsed.scheme
            host = parsed.host
            port = "\(parsed.port)"
            apiPassword = parsed.apiPassword

            if walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let scannedLabel = parsed.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                walletName = scannedLabel
            }

            isScanningQRCode = false

            if walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusMessage = "Name this wallet, then connect."
            } else {
                Task {
                    await connectNode(using: normalized)
                }
            }
        } catch {
            isScanningQRCode = false
            statusMessage = "Scan an Eclair connection QR code."
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
        (try? EclairConnectParser.parse(connectionString: rawConnectionString).host)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasSuffix(".onion") == true
    }
}
