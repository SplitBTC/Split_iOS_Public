//  ProfileView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/11/26.
//

import SwiftUI
import Foundation

private let splitBlue = Color.splitBrandBlue
private let splitPink = Color.splitBrandPink

private func alternatingProfileColor(at index: Int) -> Color {
    index.isMultiple(of: 2) ? splitBlue : splitPink
}

private struct ProfileNavItem: Identifiable {
    let id: String
    let image: String
    let title: String
    let subtitle: String
    let destination: AnyView
}

struct ProfileView: View {
    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)

    @State private var connectedLightningWalletCount = ExternalWalletStore.shared.loadWallets().count

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                profileHeaderSection

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(profileNavItems.indices, id: \.self) { index in
                            let item = profileNavItems[index]

                            navCard(
                                image: item.image,
                                iconColor: alternatingProfileColor(at: index),
                                title: item.title,
                                subtitle: item.subtitle,
                                destination: item.destination
                            )
                            .padding(.top, index == 0 ? 14 : 0)
                        }

                        Spacer(minLength: 28)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshWalletConnectionState)
    }

    private var profileNavItems: [ProfileNavItem] {
        [
            ProfileNavItem(
                id: "lightning-wallets",
                image: "bolt.fill",
                title: "Lightning Wallets",
                subtitle: lightningConnectionsSubtitle,
                destination: lightningWalletsDestination
            ),
            ProfileNavItem(
                id: "add-merchant",
                image: "storefront.fill",
                title: "Add a Merchant",
                subtitle: "Add any BTC business to our rewards program.",
                destination: AnyView(AddMerchantView())
            ),
            ProfileNavItem(
                id: "rewards-explained",
                image: "atom",
                title: "Rewards Explained",
                subtitle: "How it works.",
                destination: AnyView(RewardsInfo())
            ),
            ProfileNavItem(
                id: "support",
                image: "questionmark.bubble.fill",
                title: "Contact / Support",
                subtitle: "Questions, feedback, and product ideas.",
                destination: AnyView(SupportView())
            ),
            ProfileNavItem(
                id: "content-moderation",
                image: "flag.slash.fill",
                title: "Content Moderation",
                subtitle: "Blocking and user safety.",
                destination: AnyView(ContentModerationView())
            ),
            ProfileNavItem(
                id: "legal",
                image: "doc.text.fill",
                title: "Legal",
                subtitle: "Documents and agreements.",
                destination: AnyView(LegalView())
            ),
            ProfileNavItem(
                id: "account-management",
                image: "key.fill",
                title: "Account Management",
                subtitle: "Manage your Split account.",
                destination: AnyView(WalletManagementView())
            )
        ]
    }

    private func refreshWalletConnectionState() {
        connectedLightningWalletCount = ExternalWalletStore.shared.loadWallets().count
    }

    private var lightningConnectionsSubtitle: String {
        if connectedLightningWalletCount > 1 {
            return "Manage your Lightning connections"
        }

        if connectedLightningWalletCount == 1 {
            return "Manage your Lightning connection"
        }

        return "Connect a Lightning node or wallet"
    }

    private var lightningWalletsDestination: AnyView {
        if connectedLightningWalletCount == 0 {
            return AnyView(ProfileAddLightningWalletDestination())
        }

        return AnyView(LightningConnectionsView())
    }

    private var profileHeaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("App settings and wallet management")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.96),
                    Color.splitInputSurface.opacity(0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(splitPink.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)
                    .offset(x: 64, y: -72)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(splitBlue.opacity(0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 34)
                    .offset(x: -96, y: 58)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func navCard<Destination: View>(
        image: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)

                    Image(systemName: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(iconColor)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.60))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.78))
            }
            .padding(16)
            .background(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileAddLightningWalletDestination: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AddLightningWalletView {
            dismiss()
        }
    }
}

struct CreateLightningAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager
    @FocusState private var isUsernameFocused: Bool

    let onCreated: (WalletManager.LightningAddressInfo, MessageKeyManager.RegistrationResponse?) -> Void

    @State private var username = ""
    @State private var checkedUsername: String?
    @State private var isUsernameAvailable = false

    @State private var isCheckingAvailability = false
    @State private var isCreatingAddress = false
    @State private var errorMessage: String?

    private var normalizedUsernamePreview: String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var canCheckAvailability: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isCheckingAvailability
        && !isCreatingAddress
    }

    private var canCreateAddress: Bool {
        checkedUsername == normalizedUsernamePreview
        && isUsernameAvailable
        && !isCreatingAddress
        && !isCheckingAvailability
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Choose a username")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Text("This will become your Lightning Address.")
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        VStack(alignment: .leading, spacing: 10) {

                            Text("Username")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)

                            ViewThatFits(in: .horizontal) {
                                usernameInputRow

                                VStack(alignment: .leading, spacing: 8) {
                                    usernameField
                                    Text("@example.com")
                                        .font(.subheadline)
                                        .foregroundColor(.gray.opacity(0.5))
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                            )

                            Text("Allowed: letters, numbers, periods, underscores, and hyphens.")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !normalizedUsernamePreview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Preview")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)

                                Text("\(normalizedUsernamePreview)@example.com")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.78)
                            }
                        }

                        if let checkedUsername, isUsernameAvailable {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Available")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(splitPink)

                                Text("Your address will be created with username: \(checkedUsername)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .padding(.bottom, 150)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    isUsernameFocused = false
                }
            }
            .navigationTitle("Create Address")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionButtons
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isUsernameFocused = false
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .disabled(isCheckingAvailability || isCreatingAddress)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        isUsernameFocused = false
                    }
                    .foregroundColor(splitPink)
                }
            }
        }
    }

    private var usernameInputRow: some View {
        HStack(spacing: 8) {
            usernameField

            Text("@example.com")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var usernameField: some View {
        TextField("username", text: $username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
            .focused($isUsernameFocused)
            .foregroundColor(.white)
            .onSubmit {
                isUsernameFocused = false
            }
            .onChange(of: username) { _, _ in
                errorMessage = nil
                checkedUsername = nil
                isUsernameAvailable = false
            }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                isUsernameFocused = false
                Task { await checkAvailability() }
            }) {
                HStack {
                    if isCheckingAvailability {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Check Availability")
                            .font(.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canCheckAvailability ? splitBlue : Color.gray.opacity(0.4))
                )
            }
            .disabled(!canCheckAvailability)

            Button(action: {
                isUsernameFocused = false
                Task { await createLightningAddress() }
            }) {
                HStack {
                    if isCreatingAddress {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Create Lightning Address")
                            .font(.headline)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(canCreateAddress ? splitPink : Color.gray.opacity(0.4))
                )
            }
            .disabled(!canCreateAddress)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.black)
    }

    private func checkAvailability() async {
        errorMessage = nil

        do {
            let normalized = try walletManager.normalizedLightningUsername(username)

            isCheckingAvailability = true
            let available = try await walletManager.isLightningAddressAvailable(username: normalized)
            isCheckingAvailability = false

            checkedUsername = normalized
            isUsernameAvailable = available

            if !available {
                errorMessage = WalletManager.LightningAddressError.usernameUnavailable.localizedDescription
            }

        } catch {
            isCheckingAvailability = false
            checkedUsername = nil
            isUsernameAvailable = false
            errorMessage = error.localizedDescription
        }
    }

    private func createLightningAddress() async {
        errorMessage = nil
        isCreatingAddress = true

        do {
            let created = try await walletManager.createLightningAddress(username: username)
            var registration: MessageKeyManager.RegistrationResponse?

            do {
                registration = try await MessageKeyManager.shared.ensureRegistered(
                    authManager: authManager,
                    walletManager: walletManager
                )
            } catch {
                print("Failed to sync newly created messaging identity: \(error.localizedDescription)")
            }

            isCreatingAddress = false
            onCreated(created, registration)
            dismiss()
        } catch {
            isCreatingAddress = false
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(WalletManager())
            .environmentObject(AuthManager())
            .environmentObject(LNDWalletManager())
            .environmentObject(NWCWalletManager())
            .environmentObject(ActiveSpendWalletStore())
    }
}
